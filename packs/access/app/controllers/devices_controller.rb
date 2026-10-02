class DevicesController < ApplicationController
  include SameOrigin

  RATE_LIMIT_STORE = ActiveSupport::Cache::MemoryStore.new

  # Keyed on the socket peer: the hub has no reverse proxy, so X-Forwarded-For is client-controlled.
  rate_limit to: 10, within: 1.minute, only: :pair, store: RATE_LIMIT_STORE, by: -> { request.env["REMOTE_ADDR"] },
             with: -> { render json: { error: "Too many attempts. Wait a minute and try again." }, status: :too_many_requests }

  def pair
    device, credential = PairingToken.redeem!(params[:token].to_s, device_name: params[:name].to_s)
    render json: { device_id: device.id, credential:, event_id: device.event_id }, status: :created
  rescue PairingToken::Invalid => e
    render json: { error: e.message }, status: :unprocessable_content
  end
end
