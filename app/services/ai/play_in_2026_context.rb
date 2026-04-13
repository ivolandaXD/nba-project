# frozen_string_literal: true

module Ai
  # Contexto curado (lesões, book, notas) para os 4 jogos do play-in 2026 — mesma fonte que a rake
  # `ai:play_in_openai_package`. Injetado em `external_game_context` no user message da OpenAI.
  class PlayIn2026Context
    MATCHUPS = [
      {
        index: 1,
        slug: 'mia_cha',
        outfile: '01_mia_cha_openai_package.txt',
        research: '01_mia_cha_playin.txt',
        home_abbr: 'CHA',
        away_abbr: 'MIA',
        matchup_label: 'MIA @ CHA — East 9 vs 10',
        espn_game_id: nil,
        external: {
          book: { spread_home: '-5.5 (CHA — snapshot ESPN ~13/04/2026)', total: 228.5, notes: 'Revalidar no dia.' },
          eligibility_notes: ['Mandante na ESPN: Charlotte Hornets (MIA @ CHA). Alinhar game.home_team com CHA.'],
          extra_notes: ['Vários GTD no perímetro do Heat → volatilidade de titulares.', 'Hornets: eixo LaMelo + Miller.']
        }
      },
      {
        index: 2,
        slug: 'gsw_lac',
        outfile: '02_gsw_lac_openai_package.txt',
        research: '02_gsw_lac_playin.txt',
        home_abbr: 'LAC',
        away_abbr: 'GSW',
        matchup_label: 'GSW @ LAC — West 9 vs 10',
        espn_game_id: '401866756',
        external: {
          book: { spread_home: '-3.5 (LAC — snapshot ESPN ~13/04/2026)', total: 220.5, notes: 'Atenção fuso UTC vs local (ver estudo auxiliar).' },
          eligibility_notes: ['Clippers em casa (Intuit Dome).', 'Elenco: sem Kuminga no GSW; sem Harden no LAC (troca documentada ESPN/NBA.com).'],
          extra_notes: ['Muitas ausências OUT — titulares reais só perto do apito.']
        }
      },
      {
        index: 3,
        slug: 'orl_phi',
        outfile: '03_orl_phi_openai_package.txt',
        research: '03_orl_phi_playin.txt',
        home_abbr: 'PHI',
        away_abbr: 'ORL',
        matchup_label: 'ORL @ PHI — East 7 vs 8',
        espn_game_id: '401866757',
        external: {
          book: { spread_home: "Pick'em / ORL -1.5 (leitura ESPN — confirmar)", total: 220.5, notes: 'Snapshot ~13/04/2026.' },
          eligibility_notes: ['Sixers em casa.'],
          extra_notes: ['Narrativa imprensa: win-or-go-home; Embiid fora para este momento.']
        }
      },
      {
        index: 4,
        slug: 'por_phx',
        outfile: '04_por_phx_openai_package.txt',
        research: '04_por_phx_playin.txt',
        home_abbr: 'PHX',
        away_abbr: 'POR',
        matchup_label: 'POR @ PHX — West 7 vs 8',
        espn_game_id: '401866754',
        external: {
          book: { spread_home: '-4.5 (PHX — snapshot ESPN ~13/04/2026)', total: 219.5, notes: 'Validar horário local vs UTC (ver estudo auxiliar).' },
          eligibility_notes: ['Suns em casa.'],
          extra_notes: ['Williams OUT altera opções no 5 dos Suns — ver injury report final.']
        }
      }
    ].freeze

    def self.merge_into_input!(input, game)
      return input if skip?
      return input unless game

      m = matchup_for_game(game)
      return input unless m

      unless input[:external_game_context].present? || input['external_game_context'].present?
        input[:external_game_context] = build_package_hash(m, game)
      end

      if attach_research? && input[:external_context_text].blank? && input['external_context_text'].blank?
        path = Rails.root.join('play_in_2026_research', m[:research])
        input[:external_context_text] = File.read(path) if path.file?
      end

      input
    end

    def self.matchup_for_game(game)
      r = GameRoster.new(game: game)
      MATCHUPS.find { |m| m[:home_abbr] == r.home_abbr && m[:away_abbr] == r.away_abbr }
    end

    def self.build_package_hash(matchup_hash, game)
      ext = matchup_hash[:external]
      idx = matchup_hash[:index]
      {
        source: 'espn|manual',
        as_of_utc: '2026-04-13T12:00:00Z',
        tournament: 'NBA Play-In 2026',
        matchup_label: matchup_hash[:matchup_label],
        broadcast: 'Prime Video',
        espn_game_id: matchup_hash[:espn_game_id],
        app_game_id: game&.id,
        injuries: injuries_for_index(idx),
        eligibility_notes: ext[:eligibility_notes],
        narrative_notes: ext[:extra_notes],
        book: ext[:book],
        checklist_reminders: [
          'Revalidar lesões e GTD no dia do jogo.',
          'Se odds_snapshots estiver vazio, preencher book ou anexar odds manualmente.',
          'Play-in: rotação mais curta e minutos altos nas estrelas — mencionar se fizer sentido no texto.'
        ]
      }
    end

    def self.injuries_for_index(index)
      case index
      when 1
        [
          { team: 'MIA', player: 'Pelle Larsson', status: 'GTD', reason: 'perna inferior' },
          { team: 'MIA', player: 'Simone Fontecchio', status: 'GTD', reason: 'tornozelo' },
          { team: 'MIA', player: 'Nikola Jovic', status: 'GTD', reason: 'tornozelo' },
          { team: 'MIA', player: 'Dru Smith', status: 'GTD', reason: 'dedo do pé' },
          { team: 'CHA', player: 'PJ Hall', status: 'OUT', reason: 'tornozelo (retorno ESPN ~01/10)' }
        ]
      when 2
        [
          { team: 'GSW', player: 'Draymond Green', status: 'OUT', reason: 'costas' },
          { team: 'GSW', player: 'Quinten Post', status: 'OUT', reason: 'pé' },
          { team: 'GSW', player: 'LJ Cryer', status: 'OUT', reason: 'tornozelo' },
          { team: 'GSW', player: 'Moses Moody', status: 'OUT season', reason: 'joelho' },
          { team: 'GSW', player: 'Jimmy Butler III', status: 'OUT season', reason: 'joelho' },
          { team: 'LAC', player: 'Kawhi Leonard', status: 'OUT', reason: 'tornozelo' },
          { team: 'LAC', player: 'Isaiah Jackson', status: 'OUT', reason: 'tornozelo' },
          { team: 'LAC', player: 'Yanic Konan Niederhauser', status: 'OUT season', reason: 'pé' },
          { team: 'LAC', player: 'Bradley Beal', status: 'OUT season', reason: 'quadril' }
        ]
      when 3
        [
          { team: 'ORL', player: 'Jett Howard', status: 'GTD', reason: 'tornozelo' },
          { team: 'ORL', player: 'Jonathan Isaac', status: 'GTD', reason: 'joelho' },
          { team: 'PHI', player: 'Johni Broome', status: 'OUT', reason: 'joelho' },
          { team: 'PHI', player: 'Joel Embiid', status: 'OUT', reason: 'abdômen (retorno ESPN ~01/05)' }
        ]
      when 4
        [
          { team: 'POR', player: 'Jerami Grant', status: 'GTD', reason: 'panturrilha' },
          { team: 'POR', player: 'Damian Lillard', status: 'OUT season', reason: 'Aquiles' },
          { team: 'PHX', player: 'Mark Williams', status: 'OUT', reason: 'pé' },
          { team: 'PHX', player: 'Jordan Goodwin', status: 'GTD', reason: 'tornozelo' },
          { team: 'PHX', player: 'Collin Gillespie', status: 'GTD', reason: 'ombro' },
          { team: 'PHX', player: 'Jalen Green', status: 'GTD', reason: 'joelho' },
          { team: 'PHX', player: "Royce O'Neale", status: 'OUT', reason: 'joelho' }
        ]
      else
        []
      end
    end

    def self.skip?
      ENV['OPENAI_SKIP_PLAY_IN_CONTEXT'].to_s == '1'
    end

    def self.attach_research?
      ENV['OPENAI_ATTACH_PLAY_IN_RESEARCH'].to_s == '1'
    end
  end
end
