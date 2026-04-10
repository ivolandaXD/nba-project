require 'httparty'

module Odds
  class TheOddsApiClient
    include HTTParty
    base_uri 'https://api.the-odds-api.com/v4'

    def self.nba_odds(api_key: ENV['THE_ODDS_API_KEY'], regions: 'us', markets: 'spreads,totals,h2h')
      return nil if api_key.blank?

      new(api_key: api_key, regions: regions, markets: markets).fetch
    end

    def initialize(api_key:, regions:, markets:)
      @api_key = api_key
      @regions = regions
      @markets = markets
    end

    def fetch
      path = '/sports/basketball_nba/odds'
      query = {
        apiKey: @api_key,
        regions: @regions,
        markets: @markets,
        oddsFormat: 'american'
      }
      HttpClient.with_retry do
        self.class.get(path, query: query, timeout: 30)
      end
    end
  end
end
