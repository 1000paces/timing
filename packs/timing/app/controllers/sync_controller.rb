# The phone capture app's sync API (/sync/v1): plain JSON, authenticated by the
# paired device's credential. The event is always the device's own.
class SyncController < ApplicationController
  MAX_BATCH = 500

  before_action :authenticate_device

  def clock
    t1 = Clock.now_ms
    render json: { t1:, t2: Clock.now_ms }
  end

  def push
    entries = request.request_parameters["entries"]
    unless entries.is_a?(Array) && entries.size <= MAX_BATCH && entries.all?(Hash)
      return render json: { error: "entries must be a list of at most #{MAX_BATCH}" }, status: :unprocessable_content
    end
    result = DeviceLogIngest.call(device: @device, entries:)
    return render json: { error: result.error, ack_seq: result.ack_seq }, status: :conflict if result.error
    @device.update_columns(last_sync_at_ms: Clock.now_ms)
    render json: { ack_seq: result.ack_seq }
  end

  # Bib, name and race only — nothing else about racers leaves the hub. Plus, on a course event, the course's checkpoints and where the hub has this phone.
  def roster
    event = @device.event
    races = event.races.to_a.sort_by { [ it.scheduled_at_ms, it.name ] }
    racers = event.registrations.where.not(bib: nil).includes(:racer).order(:bib)
                  .map { { bib: it.bib, name: it.racer.full_name, race_id: it.race_id } }
    course = event.course?
    checkpoints = course ? event.checkpoints.map { { id: it.id, name: it.name } } : []
    device = course ? { checkpoint_id: @device.checkpoint_id, checkpoint_set_at_ms: @device.checkpoint_set_at_ms } : { checkpoint_id: nil, checkpoint_set_at_ms: nil }
    body = { event: { name: event.name, races: races.map { { id: it.id, name: it.name } } }, racers:, checkpoints:, device: }
    version = Digest::SHA256.hexdigest(body.to_json)[0, 16]
    return head :not_modified if request.headers["If-None-Match"] == version
    render json: body.merge(version:)
  end

  # What the hub now knows about this device's crossings.
  def status
    laps = CaptureLaps.new(@device.event)
    voided = CaptureLaps.voided_ids(@device.event)
    captures = Capture.where(device: @device).order(:device_seq).map do |capture|
      info = laps.info(capture)
      { id: capture.id, bib: laps.bib(capture), entered_bib: capture.bib, bib_source: laps.bib_source(capture).to_s, lap: info.lap,
        lap_ms: info.lap_ms, typical_lap_ms: info.typical_ms, lap_flag: info.flag, voided: voided.include?(capture.id) }
    end
    render json: { captures: }
  end

  private

  def authenticate_device
    id, credential = request.headers["Authorization"].to_s.delete_prefix("Device ").split(":", 2)
    @device = Device.authenticate(id, credential)
    return render json: { error: "unknown or revoked device" }, status: :unauthorized unless @device
    offset = request.headers["X-Clock-Offset-Ms"]
    @device.update_columns({ last_seen_at_ms: Clock.now_ms, clock_offset_ms: (Integer(offset, exception: false) if offset) }.compact)
  end
end
