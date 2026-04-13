# frozen_string_literal: true

namespace :ai do
  desc <<-DESC.squish
    Exporta JSON alinhado ao input da OpenAI (PromptCatalog + payload portfólio por jogador).
    Uso: GAME_ID=1229 bin/rails ai:export_game_payload
    Opcional: AI_EXPORT_PLAYER_LIMIT=20 AI_EXPORT_OUT=tmp/game_1229_ai_export.json
  DESC
  task export_game_payload: :environment do
    gid = ENV['GAME_ID'].presence || ENV['GAME'].presence
    raise 'Defina GAME_ID=<id> do jogo (ex.: GAME_ID=1229)' if gid.blank?

    limit = ENV.fetch('AI_EXPORT_PLAYER_LIMIT', '20').to_i
    out = ENV['AI_EXPORT_OUT'].presence

    result = Ai::GamePayloadExporter.call(game_id: gid, player_limit: limit, output_path: out)
    raise result.error.to_s unless result.success?

    if out.present?
      puts "Export OK → #{File.expand_path(out)}"
    else
      $stdout.puts result.json
    end
  end
end
