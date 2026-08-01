# frozen_string_literal: true
require "cie_eilv"

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.syntax = :expect
  end
  config.mock_with :rspec do |mocks|
    mocks.syntax = :expect
  end
  config.disable_monkey_patching!
  config.order = :random
  config.filter_run_when_matching :focus

  FIXTURES = File.expand_path("fixtures", __dir__)
end

def fixture_path(name)
  File.join(FIXTURES, name)
end

def fixture(name)
  File.read(fixture_path(name))
end
