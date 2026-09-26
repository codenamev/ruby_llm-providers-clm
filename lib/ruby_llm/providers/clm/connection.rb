# frozen_string_literal: true

module RubyLLM
  module Providers
    class CLM < Provider
      # RubyLLM picks its Faraday adapter from configuration, which is global.
      # This connection selects the local adapter for this provider alone, so
      # answering in-process never redirects anyone else's HTTP, and hands the
      # adapter the loaded model rather than leaving it to find one.
      #
      # It overrides one private method of RubyLLM's connection, which is the
      # single place this gem is coupled to RubyLLM's internals, as
      # ruby_llm-providers-laya's connection is.
      class Connection < Transport::Connection
        def initialize(provider, config, client:)
          @clm_client = client
          super(provider, config)
        end

        private

        def setup_middleware(faraday)
          faraday.request :json
          faraday.response :json
          faraday.adapter(:clm, @clm_client)
          faraday.use :llm_errors, provider: @provider
        end
      end
    end
  end
end
