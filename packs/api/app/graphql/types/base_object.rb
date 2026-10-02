module Types
  class BaseObject < GraphQL::Schema::Object
    include Authorization
  end
end
