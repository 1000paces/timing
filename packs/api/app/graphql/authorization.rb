module Authorization
  private

  def require_official!(role = "timer")
    official = context[:current_official]
    raise GraphQL::ExecutionError, "Sign in required" unless official
    raise GraphQL::ExecutionError, "Requires the #{role} role" unless official.at_least?(role)
    official
  end
end
