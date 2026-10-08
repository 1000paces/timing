# The console's index.html names hashed asset files that each rebuild replaces,
# so browsers must revalidate it; the hashed assets themselves can be cached.
class ConsoleCacheControl
  PAGES = %w[/console /console/ /console/index.html].freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    status, headers, body = @app.call(env)
    headers["cache-control"] = "no-cache" if PAGES.include?(env["PATH_INFO"])
    [ status, headers, body ]
  end
end
