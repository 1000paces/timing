# Race log rows are facts: once written they are never updated or destroyed.
module AppendOnly
  extend ActiveSupport::Concern

  def readonly? = persisted? || super
end
