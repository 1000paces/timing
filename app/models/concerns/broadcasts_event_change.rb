module BroadcastsEventChange
  extend ActiveSupport::Concern

  included { after_commit { EventBroadcast.changed(event_id) } }
end
