# frozen_string_literal: true

source "https://rubygems.org"

gemspec

# RubyLLM::Judge is unreleased: it lives on main. This gem tracks that branch
# until the release that carries it, and CI resolves it the same way.
gem "ruby_llm", github: "crmne/ruby_llm", branch: "main"

# ruby-clm is not on RubyGems yet.
gem "ruby-clm", github: "codenamev/ruby-clm", branch: "claude/clm-ruby-port-nbdg4y"

gem "minitest", "~> 5.0"
gem "rack", "~> 3.0" # the end-to-end test serves a real CLM::Server
gem "rake", "~> 13.0"
