module Types
  class PublicationEnum < BaseEnum
    value "PROVISIONAL", value: :provisional
    value "PUBLISHED", value: :published
    value "CHANGED_SINCE_PUBLISHED", value: :changed_since_published
  end
end
