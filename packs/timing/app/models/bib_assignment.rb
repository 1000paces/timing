# "Tap now, bib later": a device adds a bib to one of its own earlier captures.
class BibAssignment < DeviceEntry
  belongs_to :capture

  validates :bib, presence: true
  validate :same_device_as_capture

  # A later bib for one of a hub-side device's own crossings (a correction).
  def self.record!(capture:, bib:)
    append!(device: capture.device, capture:, bib: bib.to_s.strip)
  end

  private

  def same_device_as_capture
    errors.add(:capture, "must belong to the same device") if capture && capture.device_id != device_id
  end
end
