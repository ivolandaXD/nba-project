# frozen_string_literal: true
module NbaStats
  class OpponentInferrer
    ALIASES = {
      # stats.nba.com / team_codes usam GSW; placares e feeds externos costumam mandar GS.
      'GS' => 'GSW',
      'WSH' => 'WAS',
      'WAS' => 'WAS',
      'BRK' => 'BKN',
      'BKN' => 'BKN',
      'PHO' => 'PHX',
      'PHX' => 'PHX',
      'NO' => 'NOP',
      'NOP' => 'NOP',
      'NOK' => 'NOP',
      'CHO' => 'CHA',
      'CHA' => 'CHA'
    }.freeze

    def self.canonical_abbr(str)
      x = str.to_s.strip.upcase
      return '' if x.blank?

      ALIASES.fetch(x, x)
    end

    # roster_team: opcional (ex.: player_season_stats.team_abbr) quando players.team está vazio.
    def self.infer(pgs, game, player, roster_team: nil)
      ot = pgs.opponent_team.to_s.strip
      c = canonical_abbr(ot)
      return c if c.present?

      ih = pgs.is_home
      if ih == true
        c = canonical_abbr(game&.away_team)
        return c if c.present?
      elsif ih == false
        c = canonical_abbr(game&.home_team)
        return c if c.present?
      end

      pt = canonical_abbr(roster_team.presence || player&.team)
      ht = canonical_abbr(game&.home_team)
      at = canonical_abbr(game&.away_team)

      return at if pt.present? && pt == ht && at.present?
      return ht if pt.present? && pt == at && ht.present?

      nil
    end
  end
end
