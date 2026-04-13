# frozen_string_literal: true

class PlacedAiSuggestionLeg < ApplicationRecord
  SPORTS = %w[nba].freeze
  RESULT_STATUSES = %w[pending hit miss push void].freeze
  MATCH_METHODS = %w[
    nba_player_id
    player_record_id
    exact_name
    roster_name
    fuzzy_name
    manual_override
    unmatched
  ].freeze

  belongs_to :placed_ai_suggestion, inverse_of: :placed_ai_suggestion_legs
  belongs_to :game, optional: true
  belongs_to :player, optional: true

  validates :leg_index, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :sport, presence: true, inclusion: { in: SPORTS }
  validates :market_type, presence: true
  validates :result_status, presence: true, inclusion: { in: RESULT_STATUSES }
  validates :match_method, inclusion: { in: MATCH_METHODS }, allow_nil: true
  validates :selection_type, inclusion: { in: %w[over under] }, allow_nil: true

  validate :matched_confidence_range

  scope :ordered, -> { order(:leg_index) }
  scope :weak_match, -> { where('matched_confidence IS NULL OR matched_confidence < ?', 0.9) }

  def weak_match?
    matched_confidence.nil? || matched_confidence < 0.9 || match_method == 'fuzzy_name' || match_method == 'unmatched'
  end

  private

  def matched_confidence_range
    return if matched_confidence.blank?

    errors.add(:matched_confidence, 'deve estar entre 0 e 1') if matched_confidence.negative? || matched_confidence > 1
  end
end
