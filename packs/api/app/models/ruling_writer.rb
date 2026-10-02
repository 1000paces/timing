# The only way the API creates rulings: hub time and the signed-in official are
# set here, never taken from the client.
class RulingWriter
  def self.write(event:, official:, kind:, payload:, reason: nil)
    ruling = Ruling.new(event:, kind:, payload: payload.to_h.transform_keys(&:to_s), reason:, official_id: official.id)
    ruling.save
    ruling
  end
end
