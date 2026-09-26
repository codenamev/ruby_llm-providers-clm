# frozen_string_literal: true

require_relative "lib/ruby_llm/providers/clm/version"

Gem::Specification.new do |spec|
  spec.name = "ruby_llm-providers-clm"
  spec.version = RubyLLM::Providers::ClmProvider::VERSION
  spec.authors = ["Valentino Stoll"]
  spec.email = ["v@codenamev.com"]

  spec.summary = "CLM provider for RubyLLM: judgments and reranking from a Contrastive Language Model"
  spec.description = <<~DESC
    Adds a :clm provider to RubyLLM, so RubyLLM::Judge can answer probability,
    choice and score questions, and RubyLLM.rerank can order documents, with a
    Contrastive Language Model. It talks to clm-serve, which speaks the System One
    protocol TypeSafe's Jev does, or answers in your own process through a
    CLM::Engine, via a Faraday adapter that never opens a socket.
  DESC
  spec.homepage = "https://github.com/codenamev/ruby_llm-providers-clm"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb"] + Dir["lib/**/*.json"] + %w[README.md CHANGELOG.md LICENSE.txt]
  spec.require_paths = ["lib"]

  spec.add_dependency "faraday", ">= 2.0"
  spec.add_dependency "ruby-clm", ">= 0.1"
  # RubyLLM::Judge is on main and not in a release yet, so the version this
  # tracks is pinned in the Gemfile rather than here.
  spec.add_dependency "ruby_llm", ">= 2.0"
end
