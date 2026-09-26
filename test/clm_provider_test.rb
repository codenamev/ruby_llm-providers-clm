# frozen_string_literal: true

require "test_helper"

class CLMProviderTest < Minitest::Test
  DOCUMENTS = ["The Moon's gravitational pull.", "Photosynthesis in plants.", "Because the Earth is round."].freeze

  def judge_class(model_id = "clm-latest")
    Class.new(RubyLLM::Judge) do
      model model_id, provider: :clm
      probability :urgent, "Does this need attention today?"
    end
  end

  def triage
    Class.new(RubyLLM::Judge) do
      model "clm-latest", provider: :clm
      probability :urgent, "Does this need attention today?"
      choice :department, "Which team?" do
        billing "Payments, invoices and refunds charged twice"
        technical "Bugs and outages"
      end
      score :frustration, "How frustrated?", %w[Calm Annoyed Angry]
    end
  end

  # --- registration and catalogue

  def test_requiring_the_gem_registers_the_provider
    assert_equal RubyLLM::Providers::CLM, RubyLLM::Provider.resolve(:clm)
  end

  def test_its_models_judge_and_rerank
    models = RubyLLM.models.select { |model| model.provider == "clm" }

    assert_equal %w[clm-latest clm-raw], models.map(&:id).sort
    assert(models.all? { |model| model.capabilities.include?("judgment") })
    assert(models.all? { |model| model.modalities.output.include?("rerank") })
  end

  def test_it_needs_no_credential
    assert_empty RubyLLM::Providers::CLM.configuration_requirements
    assert_includes RubyLLM::Providers::CLM.configuration_options, :clm_client
  end

  # --- over HTTP, to clm-serve

  def test_by_default_it_talks_to_clm_serve
    provider = RubyLLM::Providers::CLM.new(RubyLLM.config)

    assert_equal "http://127.0.0.1:8700", provider.api_base
    refute_predicate provider, :local?
    assert_empty provider.headers, "a keyless clm-serve would read an empty Bearer as a bad key"
  end

  def test_clm_serve_answers_every_question_type
    with_clm_serve do
      judgment = triage.judge("My invoice was charged twice and nobody answers the phone!")

      assert_includes 0.0..1.0, judgment.urgent.probability
      assert_equal :billing, judgment.department.choice, "RubyLLM hands back the option name as a symbol"
      assert_includes 0.0..2.0, judgment.frustration.score
      assert_equal "clm-latest", judgment.model
    end
  end

  def test_clm_serve_reranks_documents
    with_clm_serve do
      rerank = RubyLLM.rerank("moon tides", DOCUMENTS, model: "clm-latest", provider: :clm)

      assert_equal 0, rerank.results.first.index
      assert_equal DOCUMENTS[0], rerank.results.first.document
      assert_equal [0, 1, 2], rerank.results.map(&:index).sort
      assert_operator rerank.results.first.score, :>, rerank.results.last.score
    end
  end

  def test_top_n_keeps_the_best_and_duplicates_keep_their_indexes
    with_clm_serve do
      rerank = RubyLLM.rerank("moon tides", ["the moon", "the moon", "plants"], model: "clm-latest",
                                                                                provider: :clm, top_n: 2)

      assert_equal [0, 1], rerank.results.map(&:index).sort
    end
  end

  def test_a_key_is_sent_and_a_wrong_one_is_refused
    with_clm_serve(api_key: "right", clm_api_key: "right") do
      assert_includes 0.0..1.0, judge_class.judge("x").urgent.probability
    end

    with_clm_serve(api_key: "right", clm_api_key: "wrong") do
      error = assert_raises(RubyLLM::UnauthorizedError) { judge_class.judge("x") }
      assert_match(/invalid API key/, error.message)
    end
  end

  def test_an_unknown_model_reports_clm_serves_reason
    with_clm_serve do
      judge = judge_class("clm-latest")
      error = assert_raises(RubyLLM::Error) { judge.judge("x", model: "gpt", assume_model_exists: true) }
      assert_match(/unknown model "gpt"/, error.message)
    end
  end

  # --- in this process

  def test_a_configured_client_answers_here
    fake = FakeCLM.new
    with_clm(clm_client: fake) do
      judgment = judge_class.judge("We were billed twice, refund it today")

      assert_in_delta 0.82, judgment.urgent.probability, 1e-9
      operation, state, _questions, options = fake.calls.first
      assert_equal [:predict, "We were billed twice, refund it today", { model: "clm-latest" }],
                   [operation, state, options]
    end
  end

  def test_a_configured_client_reranks_here
    fake = FakeCLM.new
    with_clm(clm_client: fake) do
      rerank = RubyLLM.rerank("tides", DOCUMENTS, model: "clm-raw", provider: :clm,
                                                  provider_options: { question: "Why?" })

      assert_equal [2, 1, 0], rerank.results.map(&:index), "the order the model gave"
      assert_equal [:rank, "tides", DOCUMENTS, { question: "Why?", model: "clm-raw" }], fake.calls.first
    end
  end

  def test_the_mock_engine_answers_every_question_type_in_process
    with_clm(clm_client: CLM::MockEngine.new) do
      judgment = triage.judge("My invoice was charged twice")

      assert_equal :billing, judgment.department.choice
      rerank = RubyLLM.rerank("moon tides", ["plants", "moon tides here"], model: "clm-latest", provider: :clm)
      assert_equal "moon tides here", rerank.results.first.document
    end
  end

  def test_engine_errors_become_the_statuses_clm_serve_answers_with
    with_clm(clm_client: FakeCLM.new(raises: CLM::EmbedderError.new("embedder unreachable"))) do
      assert_raises(RubyLLM::ServiceUnavailableError) { judge_class.judge("x") }
    end

    with_clm(clm_client: FakeCLM.new(raises: CLM::ModelNotFoundError.new('unknown model "gpt"'))) do
      error = assert_raises(RubyLLM::Error) { judge_class.judge("x") }
      assert_match(/unknown model/, error.message)
    end
  end

  def test_clm_local_builds_an_engine_on_first_use
    CLM.configure { |config| config.checkpoint_dir = File::NULL }
    with_clm(clm_local: true) do
      provider = RubyLLM::Providers::CLM.new(RubyLLM.config)

      assert_predicate provider, :local?
      assert_instance_of CLM::Engine, provider.client
      assert_same provider.client, provider.client
    end
  ensure
    CLM.reset!
  end

  # --- isolation, the part that would be easy to get wrong

  def test_answering_in_process_leaves_every_other_provider_on_http
    with_clm(clm_client: FakeCLM.new, openai_api_key: "sk-not-used") do
      assert_equal RubyLLM::Providers::CLM::Adapter, adapter_of(RubyLLM::Providers::CLM.new(RubyLLM.config))
      assert_equal Faraday::Adapter::NetHttp, adapter_of(RubyLLM::Providers::OpenAI.new(RubyLLM.config))
      assert_equal :net_http, RubyLLM.config.faraday_adapter, "the global setting is untouched"
    end
  end

  private

  def adapter_of(provider)
    builder = provider.connection.connection.builder
    builder.respond_to?(:adapter) && builder.adapter ? builder.adapter.klass : builder.handlers.last.klass
  end
end
