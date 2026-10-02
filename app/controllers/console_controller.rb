# Serves the ops console's page for deep links such as /console/event/<id>/starts;
# the browser app then routes by path. Real files (assets) are served before this.
class ConsoleController < ApplicationController
  class_attribute :index_path

  def show
    path = self.class.index_path || Rails.public_path.join("console/index.html")
    unless File.exist?(path)
      return render plain: "Ops console not built. Run: bin/rails console:build\n", status: :not_found
    end
    response.headers["Cache-Control"] = "no-cache"
    send_file path, type: "text/html", disposition: "inline"
  end
end
