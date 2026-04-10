# frozen_string_literal: true

module Balldontlie
  # Resolve e persiste players.bdl_player_id via busca por nome + time.
  class PlayerResolver
    def self.call(player)
      new(player).call
    end

    def initialize(player)
      @player = player
    end

    def call
      return @player.bdl_player_id if @player.bdl_player_id.present?

      token = search_token
      return nil if token.blank?

      rsp = Client.players_search(search: token, per_page: 40)
      unless rsp.success?
        DataIngestion::Logger.log('Balldontlie::PlayerResolver', level: :warn, message: 'busca falhou', code: rsp.code)
        return nil
      end

      body = rsp.parsed_response
      rows = body.is_a?(Hash) ? (body['data'] || []) : []
      abbr = @player.team.to_s.strip.upcase
      picked = pick_player(rows, abbr)
      return nil unless picked

      id = picked['id'].to_i
      return nil if id <= 0

      @player.update_columns(bdl_player_id: id) if @player.persisted?
      id
    rescue StandardError => e
      DataIngestion::Logger.log('Balldontlie::PlayerResolver', level: :error, message: e.message, player_id: @player.id)
      nil
    end

    private

    def search_token
      n = @player.name.to_s.strip
      return if n.blank?

      parts = n.split(/\s+/)
      parts.size >= 2 ? parts.last : n
    end

    def pick_player(rows, team_abbr)
      return nil if rows.blank?

      if team_abbr.present?
        match = rows.find { |r| r.dig('team', 'abbreviation').to_s.upcase == team_abbr }
        return match if match
      end

      rows.first
    end
  end
end
