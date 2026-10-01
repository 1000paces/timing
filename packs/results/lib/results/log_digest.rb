require "digest"

module Results
  # Fingerprint of everything that can change standings. Publishing and dismissing
  # suggestions don't change standings, so they are excluded.
  module LogDigest
    EXCLUDED_KINDS = %w[publish_results dismiss_suggestion].freeze

    module_function

    def compute(input)
      ids = input.captures.map { "c:#{it.id}" } +
            input.bib_assignments.map { "b:#{it.id}" } +
            input.rulings.reject { EXCLUDED_KINDS.include?(it.kind) }.map { "r:#{it.id}" }
      Digest::SHA256.hexdigest(ids.uniq.sort.join("\n"))
    end
  end
end
