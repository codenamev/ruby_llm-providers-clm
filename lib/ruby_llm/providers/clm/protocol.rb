# frozen_string_literal: true

module RubyLLM
  module Providers
    class CLM < Provider
      # The System One protocol, plus reranking through clm-serve's POST /v1/rank.
      #
      # Judgments are RubyLLM's own Protocols::SystemOne, unchanged. Reranking is
      # the primitive every CLM judgment is built on, scoring candidates against a
      # state, so a rerank query becomes the context the state head sees and each
      # document a candidate the action head sees verbatim.
      class Protocol < Protocols::SystemOne
        def rerank_url
          "v1/rank"
        end

        # +provider_options+ can add a +question+ asked about the query, or a +temperature+.
        def render_rerank_payload(query, documents, model:, top_n: nil, provider_options: {}) # rubocop:disable Lint/UnusedMethodArgument
          unless documents.is_a?(Array) && !documents.empty? && documents.all? { _1.is_a?(String) && !_1.empty? }
            raise ArgumentError, "CLM reranks one or more nonempty text documents"
          end

          { context: query, answers: documents, model: model }.merge(provider_options)
        end

        # clm-serve answers with the candidate texts, best first; this maps them back to
        # their positions, so a document that appears twice keeps both of its indexes.
        def parse_rerank_response(response, model:, documents: [], top_n: nil)
          ranked = response.body.fetch("ranked")
          unclaimed = documents.each_with_index.group_by(&:first).transform_values { |pairs| pairs.map(&:last) }
          results = ranked.map do |entry|
            index = unclaimed.fetch(entry.fetch("candidate"), []).shift or
              raise Error.new("clm-serve ranked a document it was not given", response: response)
            Rerank::Result.new(index: index, document: documents[index], score: entry.fetch("prob"))
          end
          Rerank.new(results: top_n ? results.first(top_n) : results, model: response.body["model"] || model,
                     raw: response.body)
        end

        # RubyLLM's reranking hands the parser no top_n, so it is applied here.
        def rerank(query, documents, model:, top_n: nil, provider_options: {})
          track_usage(:rerank) do
            payload = render_rerank_payload(query, documents, model: model, top_n: top_n,
                                                              provider_options: provider_options)
            response = @connection.post(rerank_url, payload, usage: @usage_tracker)
            parse_rerank_response(response, model: model, documents: documents, top_n: top_n)
          end
        end
      end
    end
  end
end
