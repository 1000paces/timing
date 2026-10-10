require "set"
require_relative "results/types"
require_relative "results/ruling_shape"
require_relative "results/active_rulings"
require_relative "results/resolver"
require_relative "results/standings"
require_relative "results/cohort_scorer"
require_relative "results/course_standings"
require_relative "results/course_scorer"
require_relative "results/publication"
require_relative "results/anomalies"
require_relative "results/engine"

# Pure results engine: Input snapshot in, standings and suggestions out.
# Must not depend on Rails or a database.
module Results
  def self.compute(input) = Engine.new(input).call
end
