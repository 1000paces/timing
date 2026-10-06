require "test_helper"

class RegistrationImportTest < ActiveSupport::TestCase
  BIKEREG = Rails.root.join("test/fixtures/files/bikereg_export.csv").read

  setup do
    @event = create_event
    @women = create_race(event: @event, category: nil, gender: "women", name_override: "Women Open")
    @cat3 = create_race(event: @event, category: "Cat 3", gender: "men")
    @masters = create_race(event: @event, category: "Masters 50+", gender: "men", age_min: 50)
  end

  CHOICES = ->(t) { { "Masters 50+ Men Cat 1/2/3" => { "race_id" => t.instance_variable_get(:@masters).id }, "T-Shirt" => { "skip" => true } } }

  def run_bikereg(csv = BIKEREG, **opts) = RegistrationImport.call(event: @event, csv:, categories: CHOICES.(self), **opts)

  # Review Focus 5: BOM, CRLF and quoted headers, as BikeReg exports them.
  test "analyze recognises BikeReg headers and lists categories with suggestions" do
    analysis = RegistrationImport.analyze(event: @event, csv: BIKEREG)
    assert_equal 17, analysis.headers.size
    assert_equal({ "first_name" => "First Name", "last_name" => "Last Name", "gender" => "Gender", "team" => "Team",
                   "license_number" => "USAC License", "age" => "Age on Event Day", "city" => "City", "state" => "State",
                   "bib" => "Bib", "category" => "Category Entered / Merchandise Ordered" }, analysis.mapping)
    rows = analysis.categories.to_h { [it.value, [it.count, it.race_id, it.skip]] }
    assert_equal({ "Women Open" => [2, @women.id, false], "Cat 3 Men" => [2, @cat3.id, false],
                   "Masters 50+ Men Cat 1/2/3" => [1, nil, false], "T-Shirt" => [1, nil, false] }, rows)
  end

  test "saved category choices are suggested next time" do
    run_bikereg
    rows = RegistrationImport.analyze(event: @event, csv: BIKEREG).categories.to_h { [it.value, [it.race_id, it.skip]] }
    assert_equal [@masters.id, false], rows["Masters 50+ Men Cat 1/2/3"]
    assert_equal [nil, true], rows["T-Shirt"]
  end

  test "imports race rows, skips merchandise, and stores no email or phone" do
    result = run_bikereg
    assert_equal [5, 0, 1], [result.created, result.updated, result.skipped]
    assert_empty result.errors
    ann = @event.registrations.joins(:rider).find_by(riders: { first_name: "Ann" })
    assert_equal [@women, nil, 41, "import", "Women Open"], [ann.race, ann.bib, ann.age, ann.source, ann.external_category]
    assert_equal %w[Boulder CO Velo 100001], [ann.rider.city, ann.rider.state, ann.rider.team, ann.rider.license_number]
    assert_equal "12", @event.registrations.joins(:rider).find_by(riders: { first_name: "Bob" }).bib
    assert_equal %w[F M M M F], @event.registrations.joins(:rider).order("riders.first_name").pluck("riders.gender")
    refute Rider.column_names.any? { it.include?("email") || it.include?("phone") }
  end

  test "an unmapped category is a row error; other rows still import" do
    result = RegistrationImport.call(event: @event, csv: BIKEREG, categories: { "T-Shirt" => { "skip" => true } })
    assert_equal [[4, "category Masters 50+ Men Cat 1/2/3 is not mapped to a race"]], result.errors.map { [it.row, it.message] }
    assert_equal 4, result.created
  end

  test "eligibility warnings use the imported age" do
    warnings = run_bikereg.warnings.map { [it.row, it.message] }
    assert_empty warnings # Cy is 52 in Masters 50+
    csv = BIKEREG.sub('"Denver","Cy","Active","Dee","CO","Spoke","","52"', '"Denver","Cy","Active","Dee","CO","Spoke","","45"')
    @event.registrations.destroy_all
    assert_equal [[4, "age 45 is below minimum 50"]], run_bikereg(csv).warnings.map { [it.row, it.message] }
  end

  # Review Focus 1
  test "re-import updates matches, keeps a bib set in the console, and lists riders not in the file" do
    run_bikereg
    ann = @event.registrations.joins(:rider).find_by(riders: { first_name: "Ann" })
    ann.update!(bib: "301")
    walk_up = RiderRegistrar.register(race: @cat3, bib: "150", rider_attrs: { first_name: "Walk", last_name: "Up", gender: "M" })
    assert walk_up.persisted?

    csv = BIKEREG.sub('"Velo","100001","41"', '"New Team","","42"') # Ann: new team, license blank this time
                 .sub(/\r\n"","Lyons","Di".*?\r\n/, "\r\n")         # Di dropped out
    result = run_bikereg(csv)
    assert_equal [0, 4], [result.created, result.updated]
    ann.reload
    assert_equal ["301", 42, "New Team", "100001"], [ann.bib, ann.age, ann.rider.team, ann.rider.license_number]
    assert_equal ["Di Eve (Cat 3 Men)"], result.not_in_file
  end

  test "a re-import can move a rider to another race" do
    run_bikereg
    result = run_bikereg(BIKEREG.sub('"Women Open","F"', '"Cat 3 Men","F"'))
    assert_equal 0, result.created
    assert_equal @cat3, @event.registrations.joins(:rider).find_by(riders: { first_name: "Ann" }).race
  end

  # Review Focus 2
  test "the same rider twice in one file for races is an error on the second row" do
    csv = BIKEREG.sub('"T-Shirt","Male"', '"Cat 3 Men","Male"')
    result = run_bikereg(csv)
    assert_equal [[5, "Cy Dee appears more than once in this file (row 4)"]], result.errors.map { [it.row, it.message] }
    assert_equal @masters, @event.registrations.joins(:rider).find_by(riders: { first_name: "Cy" }).race
  end

  test "a dry run reports the same counts and changes nothing" do
    preview = nil
    assert_no_difference(-> { Registration.count + Rider.count + CategoryMapping.count }) { preview = run_bikereg(dry_run: true) }
    real = run_bikereg
    assert_equal [preview.created, preview.updated, preview.skipped, preview.errors], [real.created, real.updated, real.skipped, real.errors]
  end

  test "unknown gender, bad dates and taken bibs are row errors" do
    csv = "first_name,last_name,gender,birth_date,bib,race\n" \
          "Ann,Lee,Q,,1,Women Open\nBob,Ray,M,not-a-date,2,Cat 3 Men\nCy,Dee,M,,3,Cat 3 Men\nDi,Eve,M,,3,Cat 3 Men\n"
    result = RegistrationImport.call(event: @event, csv:)
    assert_equal [[2, "gender Q must be M, F or X"], [3, "birth_date must be YYYY-MM-DD"], [5, "Bib has already been taken"]],
                 result.errors.map { [it.row, it.message] }
    assert_equal 1, result.created
  end

  test "a missing required column stops the import" do
    result = RegistrationImport.call(event: @event, csv: "first_name,last_name,race\nAnn,Lee,Women Open\n")
    assert_equal [[1, "missing column gender"]], result.errors.map { [it.row, it.message] }
  end

  test "column mapping lets headers differ" do
    csv = "First,Last,Sex,Number,Race\nAnn,Lee,F,301,Women Open\n"
    mapping = { "first_name" => "First", "last_name" => "Last", "gender" => "Sex", "bib" => "Number", "category" => "Race" }
    assert_equal 1, RegistrationImport.call(event: @event, csv:, mapping:).created
  end

  test "blank rows are skipped and later row numbers stay aligned" do
    csv = "first_name,last_name,gender,bib,race\nAnn,Lee,F,301,Women Open\n\n,,,,\nBob,Ray,M,101,Cat 3 Men\nCy,Dee,M,101,Cat 3 Men\n"
    result = RegistrationImport.call(event: @event, csv:)
    assert_equal 2, result.created
    assert_equal [[6, "Bib has already been taken"]], result.errors.map { [it.row, it.message] }
  end

  test "deleting a race drops its saved category mapping" do
    spare = create_race(event: @event, category: "Spare")
    CategoryMapping.create!(event: @event, external_category: "Spare Men", race: spare)
    assert_difference("CategoryMapping.count", -1) { spare.destroy! }
  end

  test "a category choice naming another event's race is a row error, not a crash" do
    stranger = create_race(event: create_event(name: "Other"))
    result = RegistrationImport.call(event: @event, csv: BIKEREG,
                                     categories: { "Masters 50+ Men Cat 1/2/3" => { "race_id" => stranger.id }, "T-Shirt" => { "skip" => true } })
    assert_equal [[4, "category Masters 50+ Men Cat 1/2/3 is not mapped to a race"]], result.errors.map { [it.row, it.message] }
    refute CategoryMapping.exists?(race_id: stranger.id)
  end

  # Final review, Important 1
  test "the same name twice in one file is a row error even when only one row has a license" do
    csv = "first_name,last_name,gender,license_number,race\nCy,Dee,M,,Cat 3 Men\nCy,Dee,M,555,Masters 50+ Men\n"
    result = RegistrationImport.call(event: @event, csv:)
    assert_equal [[3, "Cy Dee appears more than once in this file (row 2)"]], result.errors.map { [it.row, it.message] }
    assert_equal @cat3, @event.registrations.sole.race
  end

  test "two different licensed riders with the same name are both registered" do
    csv = "first_name,last_name,gender,license_number,race\nJo,Smith,M,111,Cat 3 Men\nJo,Smith,M,222,Masters 50+ Men\n"
    result = RegistrationImport.call(event: @event, csv:)
    assert_equal [2, 0, []], [result.created, result.updated, result.errors]
    assert_equal({ "111" => @cat3.id, "222" => @masters.id }, @event.registrations.joins(:rider).pluck("riders.license_number", :race_id).to_h)
  end

  # Final review, Important 2
  test "a column or category explicitly left blank is not used" do
    csv = "first_name,last_name,gender,bib,race\nAnn,Lee,F,7,Women Open\nBob,Ray,M,8,Cat 3 Men\n"
    result = RegistrationImport.call(event: @event, csv:, mapping: { "bib" => "" }, categories: { "Cat 3 Men" => { "race_id" => nil } })
    assert_equal [[3, "category Cat 3 Men is not mapped to a race"]], result.errors.map { [it.row, it.message] }
    assert_nil @event.registrations.sole.bib
  end
end
