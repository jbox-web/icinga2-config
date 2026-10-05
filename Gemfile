# frozen_string_literal: true

source 'https://rubygems.org'

gemspec

# Not published on rubygems: only a same-named gem from another author is, so the
# git source is mandatory rather than a convenience.
gem 'icinga2-api-client', git: 'https://github.com/jbox-web/icinga2-api-client'

# Same reason, one degree worse: rubygems carries 0.5.2 from the original author,
# while this fork ships zsh-escaping and aliased-command fixes under that very
# same version number. `gem 'fylla'` would silently install the other one.
gem 'fylla', git: 'https://github.com/jbox-web/fylla'

group :development, :test do
  # Dev libs
  gem 'rake'
  gem 'rspec'
  gem 'simplecov'

  # Dev tools / linter
  gem 'guard-rspec',         require: false
  gem 'rubocop',             require: false
  gem 'rubocop-performance', require: false
  gem 'rubocop-rake',        require: false
  gem 'rubocop-rspec',       require: false
end
