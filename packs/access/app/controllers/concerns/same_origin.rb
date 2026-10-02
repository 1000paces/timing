# Refuses browser requests from other origins: the session cookie must only act
# for pages the hub itself served.
module SameOrigin
  extend ActiveSupport::Concern

  included { before_action :verify_same_origin }

  private

  def verify_same_origin
    origin = request.headers["Origin"]
    return if origin.blank? || origin == request.base_url || allowed_origins.include?(origin)
    render json: { error: "cross-origin request refused" }, status: :forbidden
  end

  def allowed_origins = ENV.fetch("TIMING_ALLOWED_ORIGINS", "").split(",").map(&:strip)
end
