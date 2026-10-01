class SessionsController < ApplicationController
  include SameOrigin
  include CurrentOfficial

  RATE_LIMIT_STORE = ActiveSupport::Cache::MemoryStore.new

  rate_limit to: 5, within: 1.minute, only: :create, store: RATE_LIMIT_STORE,
             with: -> { render json: { error: "Too many attempts. Wait a minute and try again." }, status: :too_many_requests }

  def create
    official = Official.active.find_by(name: params[:name].to_s)
    if official&.authenticate_pin(params[:pin].to_s)
      reset_session
      session[:official_id] = official.id
      render json: official_json(official), status: :created
    else
      render json: { error: "Name or PIN is incorrect" }, status: :unauthorized
    end
  end

  def show
    return head(:unauthorized) unless current_official
    render json: official_json(current_official)
  end

  def destroy
    reset_session
    head :no_content
  end

  private

  def official_json(official) = { id: official.id, name: official.name, role: official.role }
end
