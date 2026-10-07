require "digest"
require "json"

# The device log checksum, shared with the phone app (frontend/capture/src/hash.ts):
# SHA-256 of the entry's canonical JSON — keys sorted, no whitespace, null fields
# omitted — without its own hash. The first entry chains from SHA-256(device id).
module DeviceHash
  module_function

  def canonical_json(entry) = JSON.generate(entry.to_h.transform_keys(&:to_s).compact.sort.to_h)

  def digest(entry) = Digest::SHA256.hexdigest(canonical_json(entry.to_h.transform_keys(&:to_s).except("hash")))

  def genesis(device_id) = Digest::SHA256.hexdigest(device_id.to_s)
end
