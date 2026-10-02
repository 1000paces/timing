module BuildHelpers
  def create_event(**attrs) = Event.create!({ name: "Test CX", date: Date.new(2026, 10, 18) }.merge(attrs))

  def create_category(**attrs) = Category.create!({ name: "Cat 3 Men", gender: "M", ability_levels: ["Cat 3"] }.merge(attrs))

  def create_start_group(event:, **attrs)
    StartGroup.create!({ event:, name: "10:00", finish_rule: { "type" => "fixed_laps", "laps" => 3 } }.merge(attrs))
  end

  def create_race(event:, start_group: create_start_group(event:), category: create_category, **attrs)
    Race.create!({ event:, start_group:, category: }.merge(attrs))
  end

  def create_rider(**attrs)
    Rider.create!({ first_name: "Ada", last_name: "Rider", gender: "M", birth_date: Date.new(1985, 6, 1), ability_level: "Cat 3" }.merge(attrs))
  end

  def register(race:, bib:, rider: create_rider) = Registration.create!(race:, rider:, bib:)

  def create_device(event:, name: "Tablet 1")
    Device.create!(event:, name:, paired_at_ms: 0, credential_digest: "test-digest")
  end

  def record_capture(device:, seq:, at_ms:, bib: nil, offset_ms: 0, id: SecureRandom.uuid_v7)
    Capture.create!(id:, event_id: device.event_id, device:, device_seq: seq, captured_at_ms: at_ms,
                    clock_offset_ms: offset_ms, bib:, prev_hash: "p#{seq}", entry_hash: "h#{seq}")
  end

  def rule(event:, kind:, created_at_ms: nil, **payload)
    Ruling.create!(event:, kind:, payload: payload.transform_keys(&:to_s), created_at_ms:)
  end

  def create_official(name: "Official #{SecureRandom.hex(3)}", role: "chief", pin: "2468")
    Official.create!(name:, role:, pin:)
  end
end
