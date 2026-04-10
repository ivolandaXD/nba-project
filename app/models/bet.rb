class Bet < ApplicationRecord
  RESULTS = %w[win loss pending].freeze
  BET_TYPES = %w[points rebounds assists steals blocks threes turnovers].freeze

  belongs_to :user
  belongs_to :game
  belongs_to :player

  validates :bet_type, presence: true, inclusion: { in: BET_TYPES }
  validates :result, inclusion: { in: RESULTS }

  def points_prop?
    bet_type == 'points'
  end

  # Over: pontos finais > linha → win; caso contrário loss (sem push).
  def apply_points_over_result!
    apply_points_over_result
    save!
  end

  def apply_points_over_result
    return unless points_prop?
    return if line.blank? || final_stat_value.blank?

    self.result = final_stat_value.to_f > line.to_f ? 'win' : 'loss'
  end
end
