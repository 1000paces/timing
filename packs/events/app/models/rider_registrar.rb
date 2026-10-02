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
      if rider.persisted? && identity_mismatch?(rider, attrs)
        registration.errors.add(:base, "License #{license} belongs to #{rider.full_name}; check the license number")
        raise ActiveRecord::Rollback
      end
      rider_ok = rider.persisted? || rider.save
      registration.errors.merge!(rider.errors) unless rider_ok
      raise ActiveRecord::Rollback unless rider_ok && registration.save
    end
    registration
  end

  def self.identity_mismatch?(rider, attrs)
    %i[first_name last_name gender].any? do |field|
      incoming = attrs[field]
      incoming.present? && incoming.to_s.strip.casecmp?(rider[field].to_s.strip) == false
    end
  end
  private_class_method :identity_mismatch?
end
