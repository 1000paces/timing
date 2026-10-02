# One stream per event. Clients refetch what they show when told it changed.
module EventBroadcast
  module_function

  def stream(event_id) = "event:#{event_id}"

  def changed(event_id) = ActionCable.server.broadcast(stream(event_id), { type: "changed", at_ms: Clock.now_ms })
end
