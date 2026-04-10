# frozen_string_literal: true

require 'httparty'

module Balldontlie
  # Cliente HTTP para api.balldontlie.io (fonte secundária).
  class Client
    include HTTParty
    base_uri ENV.fetch('BALLDONTLIE_API_BASE', 'https://api.balldontlie.io/v1')

    HEADERS = {
      'Accept' => 'application/json',
      'User-Agent' => 'nba-project-rails/1.0'
    }.freeze

    OPEN_TIMEOUT = ENV.fetch('BALLDONTLIE_OPEN_TIMEOUT', 3).to_i
    READ_TIMEOUT = ENV.fetch('BALLDONTLIE_READ_TIMEOUT', 3).to_i

    def self.players_search(search:, per_page: 25)
      HttpClient.with_retry(attempts: 3, base_sleep: 0.45) do
        get(
          '/players',
          query: { search: search.to_s.strip, per_page: per_page },
          headers: HEADERS,
          open_timeout: OPEN_TIMEOUT,
          read_timeout: READ_TIMEOUT
        )
      end
    end

    def self.stats(player_id:, season:, page: 1, per_page: 100)
      HttpClient.with_retry(attempts: 3, base_sleep: 0.45) do
        get(
          '/stats',
          query: {
            'player_ids[]' => player_id,
            'seasons[]' => season,
            per_page: per_page,
            page: page
          },
          headers: HEADERS,
          open_timeout: OPEN_TIMEOUT,
          read_timeout: READ_TIMEOUT
        )
      end
    end
  end
end
