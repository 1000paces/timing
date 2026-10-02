# Each official capturing from the console gets their own device per event, so
# their entries form one log like a tablet's.
module ConsoleDevice
  def self.name_for(official) = "Console – #{official.name}"

  def self.for(event:, official:)
    Device.find_by(event:, name: name_for(official), revoked_at_ms: nil) || Device.pair!(event:, name: name_for(official)).first
  end

  def self.find(event:, official:) = Device.find_by(event:, name: name_for(official), revoked_at_ms: nil)
end
