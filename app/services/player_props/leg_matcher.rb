# frozen_string_literal: true

module PlayerProps
  # Resolve jogador/jogo para uma perna e expõe método + confiança (auditável).
  class LegMatcher
    Result = Struct.new(
      :game_id,
      :player_id,
      :team_abbr,
      :match_method,
      :matched_confidence,
      :source_payload,
      keyword_init: true
    )

    def self.call(placed:, leg_hash:, leg_index:)
      new(placed: placed, leg_hash: leg_hash, leg_index: leg_index).call
    end

    def initialize(placed:, leg_hash:, leg_index:)
      @placed = placed
      @leg = leg_hash.is_a?(Hash) ? leg_hash.stringify_keys : {}
      @leg_index = leg_index
    end

    def call
      gid = resolve_game_id
      pid, method, conf = resolve_player(game_id: gid)

      team_raw = @leg['team_abbr'].presence || infer_team_abbr(pid)

      Result.new(
        game_id: gid,
        player_id: pid,
        team_abbr: PlayerProps::TeamAbbr.normalize(team_raw),
        match_method: method,
        matched_confidence: conf,
        source_payload: {
          'leg_index' => @leg_index,
          'raw_leg' => @leg,
          'placed_game_id' => @placed.game_id,
          'resolved_game_id' => gid
        }
      )
    end

    private

    def resolve_game_id
      explicit = @leg['game_id'].presence
      return explicit.to_i if explicit.present?

      return @placed.game_id if @placed.game_id.present?

      nil
    end

    def resolve_player(game_id:)
      if @leg['manual_override'] == true || @leg['match_method'].to_s == 'manual_override'
        pid = @leg['player_record_id'].presence || @leg['player_id'].presence
        p = Player.find_by(id: pid.to_i) if pid.present?
        return [p&.id, 'manual_override', p ? 1.0 : 0.0]
      end

      if @leg['nba_player_id'].present?
        p = Player.find_by(nba_player_id: @leg['nba_player_id'].to_i)
        return [p&.id, 'nba_player_id', p ? 1.0 : 0.0]
      end

      if @leg['player_record_id'].present?
        p = Player.find_by(id: @leg['player_record_id'].to_i)
        return [p&.id, 'player_record_id', p ? 1.0 : 0.0]
      end

      raw_name = @leg['player'].to_s.strip
      return [nil, 'unmatched', 0.0] if raw_name.blank?

      roster = roster_players_for(game_id: game_id)
      return fuzzy_match(raw_name, roster) if roster.any?

      # Sem elenco: match fraco por base global (evita silêncio, mas marca baixa confiança)
      global_match(raw_name)
    end

    def roster_players_for(game_id:)
      return [] if game_id.blank?

      game = Game.find_by(id: game_id)
      return [] unless game

      GameRoster.new(game: game, season: Nba::Season.current).all_players.to_a
    end

    def fuzzy_match(raw_name, roster)
      exact = roster.find { |p| p.name.to_s.casecmp?(raw_name) }
      return [exact.id, 'exact_name', 1.0] if exact

      down = raw_name.downcase.strip
      # Substring só com token longo o suficiente para reduzir falso positivo ("Jo" → meia dúzia).
      if down.length >= 4
        partial = roster.find do |p|
          pn = p.name.to_s.downcase
          pn.include?(down) || down.include?(pn)
        end
        if partial
          pn = partial.name.to_s.downcase
          conf = pn_matches_full_token?(pn, down) ? 0.92 : 0.84
          return [partial.id, 'roster_name', conf]
        end
      end

      last = down.split.last
      if last.present? && last.length >= 4
        ln = roster.select { |p| p.name.to_s.downcase.split.last == last }
        return [ln.first.id, 'fuzzy_name', 0.78] if ln.size == 1
        return [nil, 'fuzzy_name', 0.35] if ln.size > 1
      end

      [nil, 'unmatched', 0.0]
    end

    def pn_matches_full_token?(player_name_down, token_down)
      player_name_down.split.any? { |w| w == token_down }
    end

    def global_match(raw_name)
      exact = Player.find_by('LOWER(TRIM(name)) = ?', raw_name.downcase.strip)
      return [exact.id, 'exact_name', 0.55] if exact

      token = ActiveRecord::Base.sanitize_sql_like(raw_name.downcase.strip)
      like = Player.where('LOWER(name) LIKE ?', "%#{token}%").limit(2).to_a
      return [like.first.id, 'fuzzy_name', 0.45] if like.size == 1

      [nil, 'unmatched', 0.0]
    end

    def infer_team_abbr(player_id)
      return nil if player_id.blank?

      raw = Player.find_by(id: player_id)&.team
      PlayerProps::TeamAbbr.normalize(raw)
    end
  end
end
