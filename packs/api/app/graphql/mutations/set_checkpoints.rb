module Mutations
  class SetCheckpoints < BaseMutation
    description "Replace a course's checkpoints, in course order. Checkpoints with crossings or phones recorded at them stay, " \
                "in the same order among themselves; others may be added, removed or moved around them."
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
        error = in_use_error(existing, in_use_ids(event, existing), kept_ids)
        raise ActiveRecord::Rollback if error
        removed = event.checkpoints.where.not(id: kept_ids)
        removed_ids = removed.pluck(:id)
        # A phone at a removed checkpoint goes back to the finish; the new set time makes phones adopt it.
        Device.where(checkpoint_id: removed_ids).update_all(checkpoint_id: nil, checkpoint_set_at_ms: Clock.now_ms)
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

    # A checkpoint with crossings or phones recorded at it must stay, and those
    # checkpoints keep their order among themselves; unused ones can go anywhere.
    def in_use_error(existing, used, kept_ids)
      in_use = existing.select { used.include?(it.id) }
      if (gone = in_use.find { !kept_ids.include?(it.id) })
        return "#{gone.name} has crossings or phones recorded at it, so it can't be removed"
      end
      order = kept_ids.select { |id| used.include?(id) }
      moved = in_use.zip(order).find { |cp, id| cp.id != id }&.first
      "#{moved.name} has crossings or phones recorded at it, so it can't be moved past another such checkpoint" if moved
    end

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
