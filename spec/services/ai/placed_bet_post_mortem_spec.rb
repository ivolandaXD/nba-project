# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Ai::PlacedBetPostMortem do
  let(:user) { create(:user) }
  let(:game) { create(:game, home_team: 'LAL', away_team: 'BOS', game_date: Date.current) }
  let(:player) { create(:player, name: 'PM Player', team: 'LAL', nba_player_id: 999_013) }

  before { allow(Nba::Season).to receive(:current).and_return('2025-26') }

  let(:placed) do
    create(
      :placed_ai_suggestion,
      user: user,
      game: game,
      slip_kind: 'parlay',
      legs: [{ 'player' => player.name, 'market' => 'PTS', 'line' => '10.5' }]
    )
  end

  let(:valid_structured) do
    {
      'summary_result' => 'Resumo curto',
      'likely_causes' => ['causa'],
      'process_gaps' => [],
      'improvement_checklist' => ['passo'],
      'variance_vs_bad_process' => 'variância',
      'slate_selection_comment' => 'ok',
      'confidence_in_review' => 0.55,
      'data_quality_warning' => ''
    }
  end

  it 'persists structured contract and clears parse error when valid' do
    ai = Ai::OpenAiAnalyzer::Result.new(
      ok: true,
      prediction: 'texto formatado',
      structured: valid_structured,
      error: nil
    )
    allow(Ai::OpenAiAnalyzer).to receive(:call).and_return(ai)

    out = described_class.call(placed: placed)
    expect(out[:ok]).to be true
    placed.reload
    expect(placed.ai_post_mortem_structured_contract_ok?).to be true
    expect(placed.ai_post_mortem_parse_error).to be_blank
    expect(placed.ai_post_mortem).to include('Resumo curto')
  end

  it 'clears structured payload and prefixes parse error when invalid' do
    ai = Ai::OpenAiAnalyzer::Result.new(
      ok: true,
      prediction: 'fallback textual',
      structured: { 'summary_result' => 'só um campo' },
      error: nil
    )
    allow(Ai::OpenAiAnalyzer).to receive(:call).and_return(ai)

    described_class.call(placed: placed)
    placed.reload
    expect(placed.ai_post_mortem_structured).to eq({})
    expect(placed.ai_post_mortem_parse_error).to start_with('STRUCTURAL_INVALID:')
    expect(placed.ai_post_mortem).to eq('fallback textual')
  end
end
