# frozen_string_literal: true

def root_path
  File.expand_path(File.join(__FILE__, "..", ".."))
end

require "foreman_envsync"
load "#{root_path}/exe/foreman_envsync"

RSpec.configure do |config|
  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
