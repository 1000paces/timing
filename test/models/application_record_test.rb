require "test_helper"

class ApplicationRecordTest < ActiveSupport::TestCase
  test "ids created back to back sort in creation order" do
    ids = Array.new(50) { create_event.id }
    assert_equal ids.sort, ids
    assert_equal ids.size, ids.uniq.size
  end
end
