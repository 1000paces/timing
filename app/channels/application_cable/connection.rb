module ApplicationCable
  class Connection < ActionCable::Connection::Base
    identified_by :current_official

    def connect
      self.current_official = official_from_session || reject_unauthorized_connection
    end

    private

    def official_from_session
      session = cookies.encrypted[Rails.application.config.session_options[:key]]
      session && Official.active.find_by(id: session["official_id"])
    end
  end
end
