# The phone capture app's web manifest (public/capture-app/manifest.webmanifest).
Mime::Type.register "application/manifest+json", :webmanifest
Rack::Mime::MIME_TYPES[".webmanifest"] = "application/manifest+json"
