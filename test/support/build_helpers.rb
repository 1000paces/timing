module BuildHelpers
  def create_event(**attrs) = Event.create!({ name: "Test CX", date: Date.new(2026, 10, 18), discipline: "cyclocross" }.merge(attrs))

  RACE_SCHEDULED_AT_MS = 1_791_000_000_000

  def create_race(event:, **attrs)
    Race.create!({ event:, category: "Cat 3", gender: "men", scheduled_at_ms: RACE_SCHEDULED_AT_MS }.merge(attrs))
  end

  def create_racer(**attrs)
    Racer.create!({ first_name: "Ada", last_name: "Racer", gender: "M", birth_date: Date.new(1985, 6, 1) }.merge(attrs))
  end

  def register(race:, bib:, racer: create_racer) = Registration.create!(race:, racer:, bib:)

  def create_device(event:, name: "Tablet 1")
    Device.create!(event:, name:, paired_at_ms: 0, credential_digest: "test-digest")
  end

  def record_capture(device:, seq:, at_ms:, bib: nil, offset_ms: 0, id: SecureRandom.uuid_v7, checkpoint: nil)
    Capture.create!(id:, event_id: device.event_id, device:, device_seq: seq, captured_at_ms: at_ms,
                    clock_offset_ms: offset_ms, bib:, checkpoint_id: checkpoint&.id, prev_hash: "p#{seq}", entry_hash: "h#{seq}")
  end

  def rule(event:, kind:, created_at_ms: nil, **payload)
    Ruling.create!(event:, kind:, payload: payload.transform_keys(&:to_s), created_at_ms:)
  end

  def create_official(name: "Official #{SecureRandom.hex(3)}", role: "chief", pin: "2468")
    Official.create!(name:, role:, pin:)
  end
end
