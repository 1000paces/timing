module Mutations
  class SetCheckpoints < BaseMutation
    description "Replace a course's checkpoints, in course order. Checkpoints with crossings recorded at them stay, in place."
    argument :event_id, ID
    argument :checkpoints, [ Types::CheckpointInput ]
    argument :finish_distance_km, Float, required: false
    argument :finish_cutoff_at_ms, Types::Millis, required: false

    field :event, Types::EventType

    def resolve(event_id:, checkpoints:, finish_distance_km: nil, finish_cutoff_at_ms: nil)
      require_official!("admin")
      event = Event.find(event_id)
      existing = event.checkpoints.to_a
      used = Capture.where(checkpoint_id: existing.map(&:id)).distinct.pluck(:checkpoint_id).to_set
      wanted = checkpoints.map { it.to_h }
      kept_ids = wanted.filter_map { it[:id] }
      # A checkpoint with crossings recorded at it must stay, at the same position.
      stuck = existing.find { |cp| used.include?(cp.id) && wanted.index { |w| w[:id] == cp.id } != cp.position - 1 }
      return { event: nil, errors: [ "#{stuck.name} has crossings recorded at it, so it can't be removed or moved" ] } if stuck
      Event.transaction do
        event.checkpoints.where.not(id: kept_ids).destroy_all
        event.checkpoints.update_all("position = position + 10000") # free the positions for the new order
        wanted.each.with_index(1) do |attrs, position|
          cp = attrs[:id] ? event.checkpoints.find(attrs[:id]) : event.checkpoints.build
          cp.update!(position:, name: attrs[:name], distance_km: attrs[:distance_km], cutoff_at_ms: attrs[:cutoff_at_ms])
        end
        event.update!(finish_distance_km:, finish_cutoff_at_ms:)
      end
      { event: event.reload, errors: [] }
    rescue ActiveRecord::RecordInvalid => e
      { event: nil, errors: e.record.errors.full_messages }
    end
  end
end
