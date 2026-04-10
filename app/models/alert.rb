class Alert < ApplicationRecord
  CONDITION_TYPES = %w[over_points over_rebounds over_assists season_avg_above].freeze

  belongs_to :user
  belongs_to :player

  validates :condition_type, presence: true, inclusion: { in: CONDITION_TYPES }
  validates :threshold, presence: true
end
