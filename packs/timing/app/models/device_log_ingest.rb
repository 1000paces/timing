# Stores a batch of a phone's log entries (POST /sync/v1/push). Entries must
# continue the device's chain: the next device_seq, the previous entry's hash,
# and a hash that matches DeviceHash. Entries already stored are skipped (a
# resend after a lost ack). Anything else — a gap, a bad hash, an unknown kind,
# a fix for another device's capture — rejects the whole batch and flags the
# device as sync-stopped.
class DeviceLogIngest
  Result = Data.define(:ack_seq, :error)
  CLASSES = { "capture" => "Capture", "bib_assignment" => "BibAssignment", "capture_void" => "CaptureVoid" }.freeze

  class Mismatch < StandardError; end

  def self.call(device:, entries:) = new(device).call(entries)

  def initialize(device)
    @device = device
  end

  def call(entries)
    @device.with_lock do
      last = DeviceEntry.where(device: @device).order(:device_seq).last
      before = last&.device_seq || 0
      ack = before
      prev = last&.entry_hash || DeviceHash.genesis(@device.id)
      stored = DeviceEntry.where(device: @device, id: entries.map { it["id"].to_s }).pluck(:id, :entry_hash).to_h
      DeviceEntry.transaction(requires_new: true) do
        entries.each do |entry|
          next if stored.key?(entry["id"]) && (stored[entry["id"]] == entry["hash"] || raise(Mismatch))
          raise Mismatch unless entry["device_seq"] == ack + 1 && entry["prev_hash"] == prev && DeviceHash.digest(entry) == entry["hash"]
          raise Mismatch unless build(entry).save
          ack += 1
          prev = entry["hash"]
        end
      end
      Result.new(ack_seq: ack, error: nil)
    rescue Mismatch, ActiveRecord::RecordNotUnique
      @device.update_columns(sync_stopped_at_ms: Clock.now_ms)
      Result.new(ack_seq: before, error: "chain_mismatch")
    end
  end

  private

  def build(entry)
    klass = CLASSES[entry["kind"]]&.constantize or raise Mismatch
    attrs = { id: entry["id"], event: @device.event, device: @device, device_seq: entry["device_seq"],
              prev_hash: entry["prev_hash"], entry_hash: entry["hash"] }
    case entry["kind"]
    when "capture"
      raise Mismatch unless entry["captured_at_ms"].is_a?(Integer)
      attrs.merge!(captured_at_ms: entry["captured_at_ms"], clock_offset_ms: entry["clock_offset_ms"], bib: entry["bib"].to_s.strip.presence)
    when "bib_assignment" then attrs.merge!(capture_id: entry["capture_id"], bib: entry["bib"].to_s.strip)
    when "capture_void" then attrs.merge!(capture_id: entry["capture_id"])
    end
    klass.new(attrs)
  end
end
