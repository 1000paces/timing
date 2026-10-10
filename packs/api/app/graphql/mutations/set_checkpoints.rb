module Mutations
  class SetCheckpoints < BaseMutation
    description "Replace a course's checkpoints, in course order. Checkpoints with crossings recorded at them stay, in place."
    argument :event_id, ID
    argument :checkpoints, [ Types::CheckpointInput ]
    argument :finish_distance_km, Float, required: false, description: "Omitting it clears the finish distance (the list is replaced)"
    argument :finish_cutoff_at_ms, Types::Millis, required: false, description: "Omitting it clears the finish cutoff (the list is replaced)"

    field :event, Types::EventType

    def resolve(event_id:, checkpoints:, finish_distance_km: nil, finish_cutoff_at_ms: nil)
      require_official!("admin")
      event = Event.find(event_id)
      wanted = checkpoints.map { it.to_h }
      kept_ids = wanted.filter_map { it[:id] }
      return { event: nil, errors: [ "A checkpoint is listed more than once" ] } if kept_ids.uniq.size != kept_ids.size
      error = nil
      Event.transaction do
        event.lock!
        existing = event.checkpoints.to_a
        used = in_use_ids(event, existing)
        # A checkpoint with crossings or phones recorded at it must stay, at the same position.
        stuck = existing.find { |cp| used.include?(cp.id) && wanted.index { |w| w[:id] == cp.id } != cp.position - 1 }
        if stuck
          error = "#{stuck.name} has crossings or phones recorded at it, so it can't be removed or moved"
          raise ActiveRecord::Rollback
        end
        removed = event.checkpoints.where.not(id: kept_ids)
        removed_ids = removed.pluck(:id)
        Device.where(checkpoint_id: removed_ids).update_all(checkpoint_id: nil)
        PairingToken.where(checkpoint_id: removed_ids).update_all(checkpoint_id: nil)
        removed.update_all(removed_at_ms: Clock.now_ms, position: nil)
        event.checkpoints.update_all("position = position + 10000") # free the positions for the new order
        wanted.each.with_index(1) do |attrs, position|
          cp = attrs[:id] ? event.checkpoints.find(attrs[:id]) : event.checkpoints.build
          cp.update!(position:, name: attrs[:name], distance_km: attrs[:distance_km], cutoff_at_ms: attrs[:cutoff_at_ms])
        end
        event.update!(finish_distance_km:, finish_cutoff_at_ms:)
      end
      return { event: nil, errors: [ error ] } if error
      { event: event.reload, errors: [] }
    rescue ActiveRecord::RecordInvalid => e
      { event: nil, errors: e.record.errors.full_messages }
    rescue ActiveRecord::RecordNotFound
      { event: nil, errors: [ "That checkpoint isn't on this event's course" ] }
    end

    private

    # Checkpoints any device entry (capture or location) or active inserted crossing refers to.
    def in_use_ids(event, existing)
      ids = existing.map(&:id)
      entries = DeviceEntry.where(event:, checkpoint_id: ids).distinct.pluck(:checkpoint_id)
      rulings = Ruling.where(event:, kind: %w[insert_capture revert])
                      .map { Results::Ruling.new(id: it.id, kind: it.kind, payload: it.payload, created_at_ms: it.created_at_ms) }
      inserted = Results::ActiveRulings.new(rulings).of("insert_capture").filter_map { it.payload["checkpoint_id"] }
      (entries + inserted).to_set & ids.to_set
    end
  end
end
