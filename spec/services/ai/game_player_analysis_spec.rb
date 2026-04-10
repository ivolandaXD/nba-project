require 'rails_helper'

RSpec.describe Ai::GamePlayerAnalysis do
  let(:game) { create(:game, home_team: 'LAL', away_team: 'BOS', game_date: Date.current) }
  let(:player) { create(:player, team: 'LAL', nba_player_id: 99_999) }

  before do
    create(:player_game_stat, player: player, game: game, points: 24, rebounds: 8, game_date: game.game_date, opponent_team: 'BOS', is_home: true)
  end

  it 'creates AiPrediction with model confidence and analysis_meta' do
    structured = {
      'scenario_summary' => 'Cenário de teste',
      'probability_estimate' => 'media',
      'value_bet' => 'sim',
      'risk_level' => 'medio',
      'justification' => 'Dados consistentes.'
    }
    ai_result = Ai::OpenAiAnalyzer::Result.new(
      ok: true,
      prediction: Ai::OpenAiAnalyzer.format_display(structured),
      structured: structured,
      error: nil
    )
    allow(Ai::OpenAiAnalyzer).to receive(:call).and_return(ai_result)

    out = described_class.call(game: game, player: player, line: 20, bet_type: 'points')
    expect(out[:ok]).to be true
    pred = out[:prediction]
    expect(pred).to be_persisted
    expect(pred.confidence_score.to_i).to be_between(0, 100)
    expect(pred.analysis_meta['risk_level']).to eq('medio')
    expect(pred.output_text).to include('Resumo do cenário')
  end

  it 'returns error when OpenAI fails' do
    allow(Ai::OpenAiAnalyzer).to receive(:call).and_return(
      Ai::OpenAiAnalyzer::Result.new(ok: false, prediction: nil, structured: {}, error: 'fail')
    )
    out = described_class.call(game: game, player: player)
    expect(out[:ok]).to be false
    expect(out[:prediction]).to be_nil
  end
end
