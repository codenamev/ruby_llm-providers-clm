# frozen_string_literal: true

require "faraday"
require "json"

module RubyLLM
  module Providers
    class CLM < Provider
      # A Faraday adapter that answers clm-serve's two endpoints from a model in
      # this process.
      #
      # An adapter is any object that fills in a response; nothing obliges it to
      # open a socket. Everything around it is RubyLLM's own stack: the request
      # middleware encoded the payload, the response middleware parses what this
      # returns, and the protocol builds the judgment or rerank without knowing the
      # difference. The model's own failures become the statuses clm-serve answers
      # with, so RubyLLM raises the errors it would for the server.
      class Adapter < Faraday::Adapter
        # Faraday hands on whatever extra arguments the builder was given, which
        # is how the provider passes the model it loaded.
        def initialize(app = nil, client = nil, opts = {}, &block)
          super(app, opts, &block)
          @client = client
        end

        def call(env)
          super
          status, body = answer(env.url.path, JSON.parse(env.request_body.to_s))
          save_response(env, status, JSON.generate(body), { "content-type" => "application/json" })
          @app.call(env)
        end

        private

        def answer(path, request)
          [200, path.end_with?("/v1/rank") ? rank(request) : predict(request)]
        rescue ArgumentError => e
          [422, { "detail" => e.message }]
        rescue ::CLM::EmbedderError => e
          [502, { "detail" => e.message }]
        end

        def predict(request)
          result = @client.predict(request["state"], request["questions"], **options(request))
          result.respond_to?(:to_h) ? result.to_h : result
        end

        def rank(request)
          ranked = @client.rank(request["context"].to_s, request["answers"], question: request["question"],
                                                                              **options(request))
          { "model" => request["model"], "ranked" => ranked.map { _1.to_h.transform_keys(&:to_s) } }
        end

        def options(request)
          { model: request["model"], temperature: request["temperature"] }.compact
        end
      end
    end
  end
end

Faraday::Adapter.register_middleware(clm: RubyLLM::Providers::CLM::Adapter)
