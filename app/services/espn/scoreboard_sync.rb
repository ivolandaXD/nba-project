module Espn
  # Grade NBA via API pública da ESPN (documentação comunitária:
  # https://gist.github.com/akeaswaran/b48b02f1c94f873c6655e7129910fc3b ).
  # IDs ficam como "espn-<event_id>" em games.nba_game_id para não colidir com IDs da stats.nba.com.
  class ScoreboardSync
    Result = Struct.new(:ok, :games_count, :error, keyword_init: true) do
      def success?
        ok
      end
    end

    BASE = 'https://site.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard'.freeze

    def self.call(date: NbaStats::Calendar.scoreboard_today)
      new(date: date).call
    end

    def initialize(date:)
      @date = date
    end

    def call
      dates_param = @date.strftime('%Y%m%d')
      url = "#{BASE}?dates=#{dates_param}"
      response = HttpClient.with_retry(attempts: 3, base_sleep: 0.5) do
        HTTParty.get(
          url,
          headers: {
            'User-Agent' => 'Mozilla/5.0 (compatible; NBA-Project/1.0)',
            'Accept' => 'application/json'
          },
          open_timeout: 15,
          read_timeout: 45
        )
      end

      unless response.success?
        return Result.new(ok: false, games_count: 0, error: "ESPN scoreboard HTTP #{response.code}")
      end

      body = response.parsed_response
      unless body.is_a?(Hash)
        return Result.new(ok: false, games_count: 0, error: 'Resposta da ESPN não é JSON válido')
      end

      events = body['events'] || []
      count = 0
      zone = ActiveSupport::TimeZone['America/New_York']

      ActiveRecord::Base.transaction do
        events.each do |event|
          comp = (event['competitions'] || []).first
          next unless comp

          competitors = comp['competitors'] || []
          home = competitors.find { |c| c['homeAway'] == 'home' }
          away = competitors.find { |c| c['homeAway'] == 'away' }
          next unless home && away

          home_abbr = home.dig('team', 'abbreviation').to_s.presence
          away_abbr = away.dig('team', 'abbreviation').to_s.presence
          next if home_abbr.blank? || away_abbr.blank?

          status_text = comp.dig('status', 'type', 'shortDetail').presence ||
                        comp.dig('status', 'type', 'detail').presence ||
                        event.dig('status', 'type', 'shortDetail').presence ||
                        'scheduled'

          game_date = parse_game_date(event['date'], zone) || @date
          espn_id = event['id'].to_s
          next if espn_id.blank?

          nba_game_id = "espn-#{espn_id}"
          record = Game.find_or_initialize_by(nba_game_id: nba_game_id)
          merged_meta = merge_espn_meta(record, comp)
          hp, ap = win_probs_from_espn(comp)
          record.assign_attributes(
            home_team: home_abbr,
            away_team: away_abbr,
            game_date: game_date,
            status: status_text.to_s.strip.presence || 'scheduled',
            meta: merged_meta,
            home_win_prob: hp,
            away_win_prob: ap
          )
          record.save!
          count += 1
        end
      end

      Result.new(ok: true, games_count: count, error: nil)
    rescue StandardError => e
      Rails.logger.error("[Espn::ScoreboardSync] #{e.class}: #{e.message}")
      msg = if e.is_a?(Net::ReadTimeout) || e.is_a?(Net::OpenTimeout)
              'Timeout ao ler a API da ESPN. Tente de novo em instantes.'
            else
              e.message
            end
      Result.new(ok: false, games_count: 0, error: msg)
    end

    private

    def merge_espn_meta(record, comp)
      cur = record.meta
      cur = {} unless cur.is_a?(Hash)
      cur = cur.deep_stringify_keys
      espn = (cur['espn'] || {}).stringify_keys
      espn['odds'] = comp['odds'] if comp['odds'].present?
      espn['broadcasts'] = comp['broadcasts'] if comp['broadcasts'].present?
      espn['venue'] = comp['venue'] if comp['venue'].present?
      espn['notes'] = comp['notes'] if comp['notes'].present?
      espn['situation'] = comp['situation'] if comp['situation'].present?
      cur['espn'] = espn
      cur
    end

    # Retorna [home_win_prob, away_win_prob] em 0..1 quando a ESPN expuser (estrutura varia).
    def win_probs_from_espn(comp)
      (comp['odds'] || []).each do |o|
        next unless o.is_a?(Hash)

        ho = o['homeTeamOdds']
        ao = o['awayTeamOdds']
        next unless ho.is_a?(Hash) && ao.is_a?(Hash)

        hp = decimal_or_nil(ho['winPercentage'] || ho['moneyLineFairWinPct'])
        ap = decimal_or_nil(ao['winPercentage'] || ao['moneyLineFairWinPct'])
        next if hp.nil? || ap.nil?

        return normalize_pct_pair(hp, ap)
      end
      [nil, nil]
    end

    def decimal_or_nil(v)
      return if v.blank?

      BigDecimal(v.to_s)
    rescue StandardError
      nil
    end

    def normalize_pct_pair(hp, ap)
      hp = hp / 100 if hp > 1
      ap = ap / 100 if ap > 1
      [hp, ap]
    end

    def parse_game_date(iso_string, zone)
      return if iso_string.blank?

      zone.parse(iso_string.to_s).to_date
    rescue ArgumentError, TypeError
      nil
    end
  end
end
