# frozen_string_literal: true

require "clm" # cheap: the engine's Numo, rubyzip and Async load only when it is built
require "ruby_llm"
require_relative "clm/version"

module RubyLLM
  module Providers
    # CLM, a Contrastive Language Model, answering RubyLLM judgments and reranks.
    #
    #   class TicketTriage < RubyLLM::Judge
    #     model "clm-latest", provider: :clm
    #     probability :urgent, "Does this need attention today?"
    #   end
    #
    #   TicketTriage.judge(ticket).urgent.probability
    #   RubyLLM.rerank("what causes tides", documents, model: "clm-latest", provider: :clm)
    #
    # clm-serve speaks the System One protocol TypeSafe's Jev does, so by default
    # this is an ordinary HTTP provider pointed at it. Configure a model to answer
    # with (clm_client, or clm_local to build a CLM::Engine) and it answers in
    # this process instead, through a Faraday adapter that never opens a socket.
    class CLM < Provider
      def api_base
        @config.clm_api_base || ENV.fetch("CLM_BASE_URL", "http://127.0.0.1:8700")
      end

      # clm-serve requires a key only when it was started with CLM_API_KEY set.
      def headers
        key = @config.clm_api_key || ENV.fetch("CLM_API_KEY", nil)
        key ? { "Authorization" => "Bearer #{key}" } : {}
      end

      # Whether judgments are answered in this process rather than by clm-serve.
      def local?
        !@config.clm_client.nil? || @config.clm_local == true
      end

      def connection
        return super unless local?

        @clm_connection ||= Connection.new(self, @config, client: client)
      end

      # The model answering locally: whatever was configured, or an engine built
      # on first use. Nothing is loaded until a judgment asks for one.
      def client
        @client ||= @config.clm_client || ::CLM::Engine.new if local?
      end

      def parse_error(response)
        protocols.fetch(:system_one).new(self).parse_error_response(response) || super
      end

      class << self
        def configuration_options
          %i[clm_api_key clm_api_base clm_client clm_local]
        end

        # Nothing to authenticate against unless clm-serve was started with a key.
        def configuration_requirements
          []
        end
      end
    end
  end
end

require_relative "clm/protocol"
require_relative "clm/adapter"
require_relative "clm/connection"

RubyLLM::Providers::CLM.protocol :system_one, RubyLLM::Providers::CLM::Protocol
RubyLLM::Provider.register(:clm, RubyLLM::Providers::CLM,
                           models: File.expand_path("clm/models.json", __dir__))
