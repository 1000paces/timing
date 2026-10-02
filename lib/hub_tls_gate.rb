# With HUB_TLS=1, plain HTTP only serves the device onboarding page (to fetch the
# hub's CA certificate) and the health check; everything else needs HTTPS.
class HubTlsGate
  OPEN_PATHS = %w[/up /onboarding].freeze

  def initialize(app, enabled: ENV["HUB_TLS"] == "1")
    @app = app
    @enabled = enabled
  end

  def call(env)
    request = Rack::Request.new(env)
    return @app.call(env) if !@enabled || request.ssl? || open_path?(request.path)
    [403, { "content-type" => "text/plain" },
     ["This hub only answers over HTTPS. Set up this device first: http://#{request.host_with_port}/onboarding\n"]]
  end

  private

  def open_path?(path) = OPEN_PATHS.any? { path == it || path.start_with?("#{it}/") }
end
