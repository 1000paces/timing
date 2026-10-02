require "test_helper"

class RegistrationImportTest < ActiveSupport::TestCase
  CSV_TEXT = <<~CSV
    first_name,last_name,gender,birth_date,ability_level,team,license_number,bib,category
    Ann,Lee,F,1980-04-02,Cat 3,Velo,L1,301,Women Open
    Bob,Ray,M,1990-01-01,Cat 3,,,101,Cat 3 Men
    Cy,Dee,M,not-a-date,Cat 3,,,102,Cat 3 Men
    Di,Eve,M,1985-05-05,Cat 3,,,101,Cat 3 Men
    Ed,Fox,M,1985-05-05,Cat 3,,,103,Juniors
    Flo,Gee,M,2010-05-05,Cat 4,,,104,cat 3 men
  CSV

  setup do
    @event = create_event
    group = create_start_group(event: @event)
    create_race(event: @event, start_group: group, category: create_category(name: "Women Open", gender: "F", ability_levels: []))
    create_race(event: @event, start_group: group, category: create_category(name: "Cat 3 Men"))
  end

  # Review Focus 5
  test "good rows import; bad rows are reported by spreadsheet row number" do
    result = RegistrationImport.call(event: @event, csv: CSV_TEXT)
    assert_equal 3, result.created
    assert_equal [[4, "birth_date must be YYYY-MM-DD"], [5, "Bib has already been taken"], [6, "unknown category Juniors"]],
                 result.errors.map { [it.row, it.message] }
    assert_equal [[7, "ability level Cat 4 is not one of Cat 3"]], result.warnings.map { [it.row, it.message] }
    assert_equal %w[101 104 301], @event.registrations.order(:bib).pluck(:bib)
  end

  test "column mapping lets headers differ" do
    csv = "First,Last,Sex,Number,Race\nAnn,Lee,F,301,Women Open\n"
    mapping = { "first_name" => "First", "last_name" => "Last", "gender" => "Sex", "bib" => "Number", "category" => "Race" }
    result = RegistrationImport.call(event: @event, csv:, mapping:)
    assert_equal 1, result.created
    assert_empty result.errors
  end

  test "a missing required column stops the import" do
    result = RegistrationImport.call(event: @event, csv: "first_name,last_name,gender,category\nAnn,Lee,F,Women Open\n")
    assert_equal 0, result.created
    assert_equal [[1, "missing column bib"]], result.errors.map { [it.row, it.message] }
  end
end
