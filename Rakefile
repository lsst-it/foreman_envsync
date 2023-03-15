# frozen_string_literal: true

require "bundler/gem_tasks"
require "github_changelog_generator/task"
require "rspec/core/rake_task"
require "rubocop/rake_task"
require "foreman_envsync"

RSpec::Core::RakeTask.new(:spec)

RuboCop::RakeTask.new

GitHubChangelogGenerator::RakeTask.new :changelog do |config|
  config.future_release = ForemanEnvsync::VERSION
  config.exclude_labels = ["skip-changelog"]
  config.user = "lsst-it"
  config.project = "foreman_envsync"
end

task default: %i[spec rubocop]
