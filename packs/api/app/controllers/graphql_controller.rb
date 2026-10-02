class GraphqlController < ApplicationController
  include SameOrigin
  include CurrentOfficial

  def execute
    result = TimingSchema.execute(
      params[:query],
      variables: prepare_variables(params[:variables]),
      operation_name: params[:operationName],
      context: { current_official:, base_url: request.base_url }
    )
    render json: result
  rescue JSON::ParserError, InvalidVariables
    render json: { errors: [{ message: "variables must be a JSON object" }] }, status: :bad_request
  end

  class InvalidVariables < StandardError; end

  private

  def prepare_variables(variables)
    case variables
    when String
      return {} if variables.blank?
      parsed = JSON.parse(variables)
      parsed.is_a?(Hash) ? parsed : raise(InvalidVariables)
    when ActionController::Parameters then variables.to_unsafe_hash
    when Hash then variables
    when nil then {}
    else raise InvalidVariables
    end
  end
end
