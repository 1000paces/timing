require "test_helper"

class RegistrationImportTest < ActiveSupport::TestCase
  CSV_TEXT = <<~CSV
    first_name,last_name,gender,birth_date,team,license_number,bib,race
    Ann,Lee,F,1980-04-02,Velo,L1,301,Women Open
    Bob,Ray,M,1990-01-01,,,101,Cat 3 Men
    Cy,Dee,M,not-a-date,,,102,Cat 3 Men
    Di,Eve,M,1985-05-05,,,101,Cat 3 Men
    Ed,Fox,M,1985-05-05,,,103,Juniors
    Flo,Gee,M,2010-05-05,,,104,cat 3 men
  CSV

  setup do
    @event = create_event
    create_race(event: @event, category: nil, gender: "women", name_override: "Women Open")
    create_race(event: @event, category: "Cat 3", gender: "men", age_min: 35)
  end

  # Review Focus 5
  test "good rows import; bad rows are reported by spreadsheet row number" do
    result = RegistrationImport.call(event: @event, csv: CSV_TEXT)
    assert_equal 3, result.created
    assert_equal [[4, "birth_date must be YYYY-MM-DD"], [5, "Bib has already been taken"], [6, "unknown race Juniors"]],
                 result.errors.map { [it.row, it.message] }
    assert_equal [[7, "age 16 is below minimum 35"]], result.warnings.map { [it.row, it.message] }
    assert_equal %w[101 104 301], @event.registrations.order(:bib).pluck(:bib)
  end

  test "column mapping lets headers differ" do
    csv = "First,Last,Sex,Number,Race\nAnn,Lee,F,301,Women Open\n"
    mapping = { "first_name" => "First", "last_name" => "Last", "gender" => "Sex", "bib" => "Number", "race" => "Race" }
    result = RegistrationImport.call(event: @event, csv:, mapping:)
    assert_equal 1, result.created
    assert_empty result.errors
  end

  test "a missing required column stops the import" do
    result = RegistrationImport.call(event: @event, csv: "first_name,last_name,gender,race\nAnn,Lee,F,Women Open\n")
    assert_equal 0, result.created
    assert_equal [[1, "missing column bib"]], result.errors.map { [it.row, it.message] }
  end

  test "a UTF-8 BOM before the header is ignored" do
    result = RegistrationImport.call(event: @event, csv: "\uFEFFfirst_name,last_name,gender,bib,race\nAnn,Lee,F,301,Women Open\n")
    assert_equal 1, result.created
    assert_empty result.errors
  end

  test "blank rows are skipped and later row numbers stay aligned" do
    csv = "first_name,last_name,gender,bib,race\nAnn,Lee,F,301,Women Open\n\n,,,,\nBob,Ray,M,101,Cat 3 Men\nCy,Dee,M,101,Cat 3 Men\n"
    result = RegistrationImport.call(event: @event, csv:)
    assert_equal 2, result.created
    assert_equal [[6, "Bib has already been taken"]], result.errors.map { [it.row, it.message] }
  end

  test "header names are stripped before matching" do
    result = RegistrationImport.call(event: @event, csv: "first_name, last_name ,gender, bib,race\nAnn,Lee,F,301,Women Open\n")
    assert_equal 1, result.created
    assert_empty result.errors
  end
end
