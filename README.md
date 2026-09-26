# ruby_llm-providers-clm

The `:clm` provider for [RubyLLM](https://github.com/crmne/ruby_llm). It answers `RubyLLM::Judge`
questions and `RubyLLM.rerank` calls with [CLM](https://github.com/Contrastive-LM/CLM), a Contrastive
Language Model.

CLM scores each candidate answer against the state: a frozen Qwen3-8B encoder, two small trained
projection heads, and a softmax over their cosine similarities. Its server, `clm-serve`, speaks the
same System One protocol as [TypeSafe's Jev](https://docs.typesafe.ai), so RubyLLM judges with it
unchanged. Given a model of your own, it answers in your process instead, through
[ruby-clm](https://github.com/codenamev/ruby-clm).

```ruby
class TicketTriage < RubyLLM::Judge
  model "clm-latest", provider: :clm

  probability :urgent, "Does this need attention today?"

  choice :department, "Which team should handle this?" do
    billing   "Payments, invoices and refunds"
    technical "Bugs, outages and integrations"
    other     "Anything else"
  end

  score :frustration, "How frustrated is the customer?", ["Calm", "Annoyed", "Angry"]
end

judgment = TicketTriage.judge("We were billed twice for March. Refund it today or we cancel.")

judgment.urgent.probability  # the probability the statement holds
judgment.department.choice   # => :billing
judgment.frustration.score   # the expected level, 0..2
```

Ranking is the primitive every CLM judgment is built on, so reranking comes with it:

```ruby
rerank = RubyLLM.rerank("What causes tides on Earth?",
                        ["Photosynthesis in plants.", "The Moon's gravitational pull."],
                        model: "clm-latest", provider: :clm, top_n: 1)
rerank.results.first.document # => "The Moon's gravitational pull."
rerank.results.first.index    # => 1
```

## Install

`RubyLLM::Judge` is on RubyLLM's main branch and not in a release yet, and ruby-clm is not on
RubyGems either, so this gem tracks both and is not on RubyGems:

```ruby
gem "ruby_llm", github: "crmne/ruby_llm", branch: "main"
gem "ruby-clm", github: "codenamev/ruby-clm", require: "clm"
gem "ruby_llm-providers-clm",
    github: "codenamev/ruby_llm-providers-clm",
    require: "ruby_llm/providers/clm"
```

Requiring it registers the provider and its models. Ruby 3.2 or newer. Over HTTP it loads nothing
from ruby-clm beyond plain Ruby; the in-process engine brings Numo and loads it only when it is
built.

## Serving

Start `clm-serve` (see the [ruby-clm README](https://github.com/codenamev/ruby-clm#serve): a Qwen3-8B
pooling server on a GPU, and the 72 MB head). The provider talks to `http://127.0.0.1:8700`, or to
`CLM_BASE_URL`:

```ruby
RubyLLM.configure do |config|
  config.clm_api_base = "http://gpu-box:8700"
  config.clm_api_key = ENV["CLM_API_KEY"] # only if clm-serve was started with one
end
```

With no key it sends no `Authorization` header; a server that wants one answers 401, which raises
`RubyLLM::UnauthorizedError`.

## Models

| `model` | Answers with |
| --- | --- |
| `"clm-latest"` | the reference head, CLM-v0.1-8B |
| `"clm-raw"` | cosine in the encoder's own space, no head (an ablation) |

`clm-serve` can serve more heads (`clm-serve --model triage=runs/triage.pt`); they are not in
RubyLLM's model registry, so name them with `assume_model_exists: true`:

```ruby
TicketTriage.judge(ticket, model: "triage", assume_model_exists: true)
```

`provider_options` reach the request: `temperature:` flattens (> 1) or sharpens (< 1) the
distributions, and for a rerank `question:` is asked about the query.

## Answering in this process

Hand it a model and requests never leave the process: no `clm-serve`, just the encoder the engine
embeds with. That is also how tests substitute a double:

```ruby
RubyLLM.configure { |config| config.clm_client = CLM::Engine.new(checkpoint: CLM::Hub.download) }
```

Or let it build a `CLM::Engine` on first use, configured through `CLM.configure`:

```ruby
RubyLLM.configure { |config| config.clm_local = true }
```

The engine's own failures become the statuses `clm-serve` would have answered with, so an unknown
model raises a `RubyLLM::Error` carrying its reason and an unreachable encoder a
`RubyLLM::ServiceUnavailableError`.

## How it works

Judgments go through RubyLLM's own `Protocols::SystemOne`, unchanged: clm-serve answers exactly
what TypeSafe's API answers. Reranking adds the three seams RubyLLM asks of a protocol, posting the
query and documents to clm-serve's `POST /v1/rank` and mapping the ranked texts back to their
positions (a document given twice keeps both indexes).

In process, a Faraday adapter answers instead of a socket, and a connection selects it for this
provider alone, so choosing it never redirects any other provider's HTTP and the global
`faraday_adapter` setting is left as it was. The one coupling to RubyLLM's internals is
`Connection#setup_middleware`, as in
[ruby_llm-providers-laya](https://github.com/codenamev/ruby_llm-providers-laya), which is why it
tracks main rather than a release.

## What it is good at, and what it is not

The CLM authors report that CLM-8B performs on par with Jev across computer-use, gaming and
tool-calling tasks with up to 9× lower latency, and that fine-tuned heads set state-of-the-art
verifier results on Terminal-Bench 2.1 and DeepSWE. Those are their measurements, in the
[CLM README](https://github.com/Contrastive-LM/CLM#results); this gem has not re-run them. What is
structural: it needs a GPU for its encoder, where Laya runs on a CPU; answers for a repeated state or
candidate come from a cache instead of the encoder; and a state longer than the encoder's context
(2048 tokens by default) is truncated.

## Development

```bash
bundle install
bundle exec rake test   # doubles and the mock engine stand in for the model; no GPU needed
```

The tests serve a real `CLM::Server` to RubyLLM through a Rack adapter instead of a socket, so the
wire format is checked end to end in both directions.

## License

MIT. CLM was developed by the Contrastive-LM authors and is Apache 2.0, as are the CLM-8B weights.
