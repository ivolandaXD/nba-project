# frozen_string_literal: true

module PlayerProps
  # Convenção: abreviatura de time em MAIÚSCULAS (3 letras típicas NBA), alinhada a `games.home_team` /
  # `away_team` e `players.team` após normalização via GameRoster (canonical_abbr quando existir).
  #
  # Não substitui uma tabela `teams`; evita múltiplas grafias ("lal" vs "LAL") na persistência de pernas.
  module TeamAbbr
    module_function

    def normalize(raw)
      s = raw.to_s.strip
      return nil if s.blank?

      GameRoster.normalize_abbr(s).presence || s.upcase
    end
  end
end
