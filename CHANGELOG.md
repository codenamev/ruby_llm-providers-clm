# Changelog

## 0.1.0

First release.

- Adds the `:clm` provider to RubyLLM. `RubyLLM::Judge` questions go to `clm-serve`
  (`http://127.0.0.1:8700`, `CLM_BASE_URL` or `config.clm_api_base`) through RubyLLM's own
  System One protocol, sending `clm_api_key` only when one is set.
- `RubyLLM.rerank` with `provider: :clm` ranks documents through `clm-serve`'s `/v1/rank`,
  honouring `top_n` and keeping the indexes of repeated documents.
- Answers both in this process instead when `config.clm_client` is set (a `CLM::Engine`, or anything
  answering `predict` and `rank`) or `config.clm_local` builds an engine, mapping its failures to the
  statuses `clm-serve` returns.
- Registers `clm-latest` and `clm-raw` in RubyLLM's model registry.
