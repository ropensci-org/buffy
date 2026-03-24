source 'https://rubygems.org'

if ENV["CUSTOM_RUBY_VERSION"]
  ruby ENV["CUSTOM_RUBY_VERSION"]
end

gem 'octokit'
gem 'sinatra', '4.0.0'
gem 'sinatra-contrib', '4.0.0'
gem 'openssl'
gem 'puma'
gem 'connection_pool', '< 3.0'
gem 'public_suffix', '< 7.0'
gem 'sidekiq'
gem 'bibtex-ruby'
gem 'faraday'
gem 'faraday-retry'
gem 'serrano'
gem 'rexml'
gem 'github-linguist'
gem 'licensee'
gem 'issue'
gem 'chronic'

group :test do
  gem 'rack-test'
  gem 'rspec'
  gem 'webmock'
end

eval_gemfile './Gemfile_custom'
