# frozen_string_literal: true

module PlayerProps
  # Normaliza mercado/linha/seleção vindos do JSONB de pernas (UI livre).
  class LegMarketNormalizer
    Result = Struct.new(:market_type, :selection_type, :line_value, keyword_init: true)

    def self.call(leg_hash)
      new(leg_hash).call
    end

    def initialize(leg_hash)
      @h = leg_hash.is_a?(Hash) ? leg_hash.stringify_keys : {}
    end

    def call
      market_raw = @h['market'].to_s.downcase
      line = parse_line(@h['line'])
      selection = infer_selection(market_raw, @h['selection'], @h['side'])

      Result.new(
        market_type: infer_market_type(market_raw),
        selection_type: selection,
        line_value: line
      )
    end

    private

    def parse_line(val)
      s = val.to_s.gsub(',', '.').strip
      return nil if s.blank?

      Float(s)
    rescue ArgumentError
      nil
    end

    def infer_selection(market_raw, sel, side)
      s = [sel, side].compact.map { |x| x.to_s.downcase.strip }.reject(&:blank?).join(' ')
      return 'under' if s.include?('under') || market_raw.include?('under')
      return 'over' if s.include?('over') || market_raw.include?('over')

      # "20+ PTS" / alt → over na prática
      return 'over' if market_raw.include?('+')

      'over'
    end

    def infer_market_type(market_raw)
      case market_raw
      when /point|pts|pontos/
        'points'
      when /rebound|reb|rebote/
        'rebounds'
      when /assist|ast/
        'assists'
      when /three|3pm|3pt|triplo|bola.*tr[eê]s/
        'threes'
      when /steal|stl|roub/
        'steals'
      when /block|blk|toco/
        'blocks'
      when /turnover|tov|bola.*perdida/
        'turnovers'
      else
        'unknown'
      end
    end
  end
end
