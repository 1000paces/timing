module Results
  module Publication
    module_function

    def for(race_id, rulings, digest)
      published = rulings.latest_by("publish_results") { it.payload["race_id"] }[race_id]
      return :provisional unless published
      published.payload["result_digest"] == digest ? :published : :changed_since_published
    end
  end
end
