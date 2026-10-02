# Registers a rider for a race, creating the rider unless one with the same
# license number exists. Rider and registration succeed or fail together.
class RiderRegistrar
  def self.register(race:, bib:, rider_attrs:)
    attrs = rider_attrs.to_h.transform_keys(&:to_sym)
    registration = nil
    Registration.transaction do
      license = attrs[:license_number].presence
      rider = (license && Rider.find_by(license_number: license)) || Rider.new(attrs)
      registration = Registration.new(race:, rider:, bib:)
      rider_ok = rider.persisted? || rider.save
      registration.errors.merge!(rider.errors) unless rider_ok
      raise ActiveRecord::Rollback unless rider_ok && registration.save
    end
    registration
  end
end
