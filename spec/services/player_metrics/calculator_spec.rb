require 'rails_helper'

RSpec.describe PlayerMetrics::Calculator do
  let(:player) { create(:player, team: 'LAL') }
  let(:game_home) { create(:game, home_team: 'LAL', away_team: 'BOS') }
  let(:game_away) { create(:game, home_team: 'BOS', away_team: 'LAL') }

  before do
    create(:player_game_stat, player: player, game: game_home, points: 10, is_home: true, opponent_team: 'BOS', game_date: 5.days.ago.to_date)
    create(:player_game_stat, player: player, game: game_away, points: 30, is_home: false, opponent_team: 'BOS', game_date: 3.days.ago.to_date)
  end

  it 'computes season and home/away averages' do
    calc = described_class.new(player, stat_key: :points)
    expect(calc.season_avg).to eq(20.0)
    expect(calc.home_avg).to eq(10.0)
    expect(calc.away_avg).to eq(30.0)
  end

  it 'computes vs opponent average case-insensitively' do
    calc = described_class.new(player, stat_key: :points, opponent_team: 'bos')
    expect(calc.vs_opponent_avg).to eq(20.0)
  end

  it 'computes over line rate' do
    calc = described_class.new(player, stat_key: :points, line: 15)
    expect(calc.over_line_rate).to eq(50.0)
  end

  it 'computes variance and coefficient of variation for points' do
    calc = described_class.new(player, stat_key: :points)
    expect(calc.variance_rounded).to eq(200.0)
    expect(calc.std_dev).to eq(14.14)
    expect(calc.coefficient_of_variation).to eq(0.707)
  end

  it 'computes pct above thresholds for points only' do
    calc = described_class.new(player, stat_key: :points)
    expect(calc.pct_games_above(15)).to eq(50.0)
    expect(calc.pct_games_above(20)).to eq(50.0)
    expect(calc.pct_games_above(25)).to eq(50.0)
  end

  it 'computes minutes average and usage proxy' do
    calc = described_class.new(player, stat_key: :points)
    expect(calc.minutes_avg).to eq(32.5)
    expect(calc.usage_rate).to eq(18.0)
    expect(calc.points_per_minute).to eq(0.615)
  end

  context 'with hot streak' do
    let(:d0) { Date.current }
    let(:g5) { create(:game, home_team: 'LAL', away_team: 'NYK', game_date: d0) }
    let(:g3) { create(:game, home_team: 'LAL', away_team: 'MIA', game_date: d0 - 1) }
    let(:g4) { create(:game, home_team: 'MIA', away_team: 'LAL', game_date: d0 - 2) }

    before do
      create(:player_game_stat, player: player, game: g5, points: 40, is_home: true, opponent_team: 'NYK', game_date: g5.game_date)
      create(:player_game_stat, player: player, game: g3, points: 40, is_home: true, opponent_team: 'MIA', game_date: g3.game_date)
      create(:player_game_stat, player: player, game: g4, points: 40, is_home: false, opponent_team: 'MIA', game_date: g4.game_date)
    end

    it 'detects hot streak when last three games are above season mean' do
      calc = described_class.new(player, stat_key: :points)
      expect(calc.streak_status).to eq('hot')
    end
  end

  describe '.cached_payload' do
    it 'returns for_ai and scorer_inputs' do
      Rails.cache.clear
      payload = described_class.cached_payload(player, stat_key: :points, line: 15, opponent_team: 'BOS')
      expect(payload[:for_ai]).to include(:season_avg_points, :coefficient_of_variation, :streak_status)
      expect(payload[:scorer_inputs]).to include(:trend_last_10, :streak_status)
    end
  end
end
