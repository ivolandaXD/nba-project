class TeamSeasonStat < ApplicationRecord
  validates :season, :team_abbr, presence: true
  validates :team_abbr, uniqueness: { scope: :season }
end
