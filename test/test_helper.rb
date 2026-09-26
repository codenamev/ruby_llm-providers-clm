# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "rack"
require "ruby_llm/providers/clm"

# Stands in for a CLM model. The adapter only ever sends it `predict` and `rank`.
class FakeCLM
  attr_reader :calls

  def initialize(answers: nil, raises: nil)
    @answers = answers
    @raises = raises
    @calls = []
  end

  def predict(state, questions, **options)
    record(:predict, state, questions, options)
    { "model" => options[:model],
      "answers" => @answers || questions.keys.to_h { |id| [id.to_s, { "type" => "noul", "noul" => 0.82 }] },
      "usage" => { "billing_units" => questions.size, "input_tokens" => 38, "output_tokens" => 0 } }
  end

  # Ranks the answers in reverse, so an order that survives proves it came from here.
  def rank(context, answers, **options)
    record(:rank, context, answers, options)
    answers.reverse.each_with_index.map do |candidate, position|
      CLM::Ranking.new(rank: position + 1, candidate: candidate, prob: 1.0 / (position + 2))
    end
  end

  private

  def record(operation, *arguments)
    @calls << [operation, *arguments]
    raise @raises if @raises
  end
end

# A Faraday adapter that hands requests to a Rack app in this process: a real
# CLM::Server with no socket in between, so the wire format is tested end to end
# through RubyLLM's own HTTP stack.
class RackAdapter < Faraday::Adapter
  class << self
    attr_accessor :app
  end

  def call(env)
    super
    rack_env = Rack::MockRequest.env_for(env.url.to_s, method: env.method.to_s.upcase,
                                                       input: env.request_body.to_s)
    env.request_headers.each { |name, value| rack_env["HTTP_#{name.upcase.tr("-", "_")}"] = value }
    rack_env["CONTENT_TYPE"] = env.request_headers["Content-Type"]
    status, headers, body = self.class.app.call(rack_env)
    save_response(env, status, body.to_enum(:each).to_a.join, headers.to_h)
    @app.call(env)
  end
end
Faraday::Adapter.register_middleware(clm_test_rack: RackAdapter)

def with_clm(**settings)
  previous = settings.keys.to_h { |key| [key, RubyLLM.config.public_send(key)] }
  RubyLLM.configure { |config| settings.each { |key, value| config.public_send("#{key}=", value) } }
  yield
ensure
  RubyLLM.configure { |config| previous.each { |key, value| config.public_send("#{key}=", value) } }
end

# clm-serve (with the mock engine: character n-grams, no GPU) behind RubyLLM's HTTP stack.
def with_clm_serve(api_key: nil, **settings, &)
  RackAdapter.app = CLM::Server.new(CLM::MockEngine.new, api_key: api_key, ui: false)
  with_clm(faraday_adapter: :clm_test_rack, **settings, &)
end
