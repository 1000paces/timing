class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # UUIDv7: globally unique and time-ordered, so records made on a hub merge into the cloud.
  before_create { self.id ||= SecureRandom.uuid_v7 }
end
