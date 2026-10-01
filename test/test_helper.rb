ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
Dir[File.expand_path("support/**/*.rb", __dir__)].sort.each { require it }

module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)
    include BuildHelpers
  end
end
