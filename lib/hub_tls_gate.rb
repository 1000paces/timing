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
    return @app.call(env) if !@enabled || secure?(env) || open_path?(request.path)
    [403, { "content-type" => "text/plain" },
     ["This hub only answers over HTTPS. Set up this device first: http://#{request.host_with_port}/onboarding\n"]]
  end

  private

  # Only the HTTPS CGI variable, which Puma sets on SSL listeners alone. Rack's
  # request.ssl? also trusts X-Forwarded-* headers, which any client can send.
  def secure?(env) = %w[on https].include?(env["HTTPS"])

  def open_path?(path) = OPEN_PATHS.any? { path == it || path.start_with?("#{it}/") }
end
