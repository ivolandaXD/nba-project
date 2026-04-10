# frozen_string_literal: true

# Temporada NBA no formato stats.nba.com (ex.: 2025-26). Sobrescreva com ENV["NBA_SEASON"].
module Nba
  module Season
    def self.current
      ENV.fetch('NBA_SEASON', '2025-26')
    end

    # Intervalo aproximado da temporada regular (1/out do 1º ano → 30/set do 2º ano).
    # Usado para agregar player_game_stats em splits jogador × adversário.
    def self.date_range_for(season_str)
      m = season_str.to_s.strip.match(/\A(\d{4})-(\d{2})\z/)
      return nil unless m

      y = m[1].to_i
      Date.new(y, 10, 1)..Date.new(y + 1, 9, 30)
    end

    # balldontlie.io usa o ano de início (ex.: 2025-26 → 2025).
    def self.balldontlie_season_int(season_str = current)
      m = season_str.to_s.strip.match(/\A(\d{4})/)
      m ? m[1].to_i : Time.current.year
    end
  end
end
