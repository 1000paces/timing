# One stream per event. Clients refetch what they show when told it changed.
module EventBroadcast
  module_function

  def stream(event_id) = "event:#{event_id}"

  # Runs after commit, so a cable failure must never fail the write that already succeeded.
  def changed(event_id)
    ActionCable.server.broadcast(stream(event_id), { type: "changed", at_ms: Clock.now_ms })
  rescue StandardError => e
    Rails.logger.warn("[broadcast] event #{event_id}: #{e.class}: #{e.message}")
    nil
  end
end
