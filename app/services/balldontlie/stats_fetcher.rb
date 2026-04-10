# frozen_string_literal: true

module Balldontlie
  # Pagina /stats para um jogador BDL e temporada (ano inicial).
  class StatsFetcher
    def self.all_stats(bdl_player_id:, season_int:)
      page = 1
      acc = []
      loop do
        rsp = Client.stats(player_id: bdl_player_id, season: season_int, page: page)
        break unless rsp.success?

        body = rsp.parsed_response
        data = body.is_a?(Hash) ? (body['data'] || []) : []
        acc.concat(data)

        meta = body['meta'] || {}
        nxt = meta['next_page']
        break if nxt.blank? || nxt.to_i <= page

        page = nxt.to_i
        sleep(ENV.fetch('BALLDONTLIE_PAGE_DELAY_SEC', 0.15).to_f)
        break if page > 200
      end
      acc
    end
  end
end
