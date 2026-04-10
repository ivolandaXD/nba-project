module Odds
  class GameOddsImporter
    Result = Struct.new(:ok, :snapshots_count, :error, keyword_init: true) do
      def success?
        ok
      end
    end

    def self.call(game, source: 'the-odds-api')
      new(game, source: source).call
    end

    def initialize(game, source:)
      @game = game
      @source = source
    end

    def call
      response = TheOddsApiClient.nba_odds
      if response.nil?
        return Result.new(ok: false, snapshots_count: 0, error: 'THE_ODDS_API_KEY is not set')
      end
      unless response.success?
        return Result.new(ok: false, snapshots_count: 0, error: "Odds API HTTP #{response.code}")
      end

      events = response.parsed_response
      return Result.new(ok: false, snapshots_count: 0, error: 'Empty odds payload') unless events.is_a?(Array)

      matched = find_event(events)
      return Result.new(ok: false, snapshots_count: 0, error: 'No matching event for this game') unless matched

      count = persist_event(matched)
      Result.new(ok: true, snapshots_count: count, error: nil)
    rescue StandardError => e
      Rails.logger.error("[GameOddsImporter] #{e.class}: #{e.message}")
      Result.new(ok: false, snapshots_count: 0, error: e.message)
    end

    private

    def find_event(events)
      home = normalize(@game.home_team)
      away = normalize(@game.away_team)
      events.find do |ev|
        h = normalize(ev['home_team'])
        a = normalize(ev['away_team'])
        (h == home && a == away) || (h == away && a == home)
      end
    end

    def normalize(name)
      name.to_s.downcase.gsub(/\s+/, ' ').strip
    end

    def persist_event(event)
      count = 0
      bookmakers = event['bookmakers'] || []
      bookmakers.each do |book|
        book_key = book['key']
        (book['markets'] || []).each do |market|
          market_type = market['key']
          (market['outcomes'] || []).each do |outcome|
            OddsSnapshot.create!(
              game: @game,
              player: nil,
              market_type: "#{market_type}:#{outcome['name']}",
              line: outcome['point'],
              odds: outcome['price'].to_s,
              source: "#{@source}:#{book_key}"
            )
            count += 1
          end
        end
      end
      count
    end
  end
end
