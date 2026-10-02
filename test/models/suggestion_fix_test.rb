require "test_helper"

class SuggestionFixTest < ActiveSupport::TestCase
  UNASSIGNED = { "kind" => "assign_bib", "capture_id" => "c", "bib" => nil }.freeze
  FLAG = { "kind" => "flag_finish", "bib" => "2" }.freeze
  INSERT = { "kind" => "insert_capture", "bib" => "2", "at_ms" => 5 }.freeze

  test "missing" do
    assert_equal [], SuggestionFix.missing(nil)
    assert_equal [], SuggestionFix.missing({ "kind" => "void_capture", "capture_id" => "c" })
    assert_equal ["bib"], SuggestionFix.missing(UNASSIGNED)
    assert_equal ["capture_id"], SuggestionFix.missing(FLAG)
  end

  test "complete fills the bib on an unassigned fix" do
    assert_equal "7", SuggestionFix.complete(UNASSIGNED, bib: "7")["bib"]
  end

  test "complete fills capture_id on flag_finish" do
    assert_equal "c9", SuggestionFix.complete(FLAG, capture_id: "c9")["capture_id"]
  end

  test "complete does not add capture_id to fixes that do not take it" do
    refute SuggestionFix.complete(INSERT, capture_id: "c9", bib: "3").key?("capture_id")
    assert_equal "2", SuggestionFix.complete(INSERT, bib: "3")["bib"]
  end

  test "complete never overwrites supplied values" do
    assert_equal "c", SuggestionFix.complete(UNASSIGNED, capture_id: "x", bib: nil)["capture_id"]
    assert_equal "2", SuggestionFix.complete(FLAG, bib: "9")["bib"]
    full = { "kind" => "flag_finish", "bib" => "2", "capture_id" => "k" }
    assert_equal "k", SuggestionFix.complete(full, capture_id: "z")["capture_id"]
  end

  test "complete of nil is nil" do
    assert_nil SuggestionFix.complete(nil, capture_id: "c", bib: "1")
  end
end
