# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# Note that this schema.rb definition is the authoritative source for your
# database schema. If you need to create the application database on another
# system, you should be using db:schema:load, not running all the migrations
# from scratch. The latter is a flawed and unsustainable approach (the more migrations
# you'll amass, the slower it'll run and the greater likelihood for issues).
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema.define(version: 2026_04_11_120000) do

  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "ai_predictions", force: :cascade do |t|
    t.bigint "game_id"
    t.bigint "player_id"
    t.jsonb "input_data"
    t.text "output_text"
    t.decimal "confidence_score"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "analysis_meta", default: {}, null: false
    t.index ["game_id", "player_id"], name: "index_ai_predictions_on_game_id_and_player_id"
    t.index ["game_id"], name: "index_ai_predictions_on_game_id"
    t.index ["player_id"], name: "index_ai_predictions_on_player_id"
  end

  create_table "alerts", force: :cascade do |t|
    t.bigint "user_id"
    t.bigint "player_id"
    t.string "condition_type"
    t.decimal "threshold"
    t.boolean "is_active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["player_id"], name: "index_alerts_on_player_id"
    t.index ["user_id", "is_active"], name: "index_alerts_on_user_id_and_is_active"
    t.index ["user_id"], name: "index_alerts_on_user_id"
  end

  create_table "bets", force: :cascade do |t|
    t.bigint "user_id"
    t.bigint "game_id"
    t.bigint "player_id"
    t.string "bet_type"
    t.decimal "line"
    t.string "odds"
    t.string "result", default: "pending", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "final_stat_value", precision: 8, scale: 2
    t.index ["game_id"], name: "index_bets_on_game_id"
    t.index ["player_id"], name: "index_bets_on_player_id"
    t.index ["user_id", "created_at"], name: "index_bets_on_user_id_and_created_at"
    t.index ["user_id"], name: "index_bets_on_user_id"
  end

  create_table "comments", force: :cascade do |t|
    t.bigint "user_id"
    t.bigint "game_id"
    t.text "content"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["game_id"], name: "index_comments_on_game_id"
    t.index ["user_id"], name: "index_comments_on_user_id"
  end

  create_table "games", force: :cascade do |t|
    t.date "game_date"
    t.string "home_team"
    t.string "away_team"
    t.string "status"
    t.string "nba_game_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "meta", default: {}, null: false
    t.decimal "home_win_prob", precision: 6, scale: 4
    t.decimal "away_win_prob", precision: 6, scale: 4
    t.index ["game_date"], name: "index_games_on_game_date"
    t.index ["meta"], name: "index_games_on_meta", using: :gin
    t.index ["nba_game_id"], name: "index_games_on_nba_game_id", unique: true, where: "(nba_game_id IS NOT NULL)"
  end

  create_table "odds_snapshots", force: :cascade do |t|
    t.bigint "game_id"
    t.bigint "player_id"
    t.string "market_type"
    t.decimal "line"
    t.string "odds"
    t.string "source"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["game_id", "market_type", "source"], name: "index_odds_snapshots_on_game_id_and_market_type_and_source"
    t.index ["game_id"], name: "index_odds_snapshots_on_game_id"
    t.index ["player_id"], name: "index_odds_snapshots_on_player_id"
  end

  create_table "player_game_stats", force: :cascade do |t|
    t.bigint "player_id"
    t.bigint "game_id"
    t.date "game_date"
    t.string "opponent_team"
    t.boolean "is_home"
    t.decimal "minutes"
    t.integer "points"
    t.integer "assists"
    t.integer "rebounds"
    t.integer "steals"
    t.integer "blocks"
    t.integer "turnovers"
    t.integer "fgm"
    t.integer "fga"
    t.decimal "fg_pct"
    t.integer "three_pt_made"
    t.integer "three_pt_attempted"
    t.decimal "three_pt_pct"
    t.integer "ftm"
    t.integer "fta"
    t.decimal "ft_pct"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "data_source"
    t.index ["game_date"], name: "index_player_game_stats_on_game_date"
    t.index ["game_id"], name: "index_player_game_stats_on_game_id"
    t.index ["player_id", "game_date"], name: "index_pgs_on_player_id_and_game_date"
    t.index ["player_id", "game_id"], name: "index_player_game_stats_on_player_id_and_game_id", unique: true
    t.index ["player_id"], name: "index_player_game_stats_on_player_id"
  end

  create_table "player_opponent_splits", force: :cascade do |t|
    t.bigint "player_id", null: false
    t.string "opponent_team", null: false
    t.string "season", null: false
    t.integer "gp", null: false
    t.decimal "avg_minutes", precision: 8, scale: 2
    t.decimal "avg_points", precision: 8, scale: 2
    t.decimal "avg_rebounds", precision: 8, scale: 2
    t.decimal "avg_assists", precision: 8, scale: 2
    t.decimal "avg_steals", precision: 8, scale: 2
    t.decimal "avg_blocks", precision: 8, scale: 2
    t.decimal "avg_turnovers", precision: 8, scale: 2
    t.decimal "avg_fgm", precision: 8, scale: 2
    t.decimal "avg_fga", precision: 8, scale: 2
    t.decimal "avg_three_pt_made", precision: 8, scale: 2
    t.decimal "avg_three_pt_attempted", precision: 8, scale: 2
    t.datetime "synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["player_id", "opponent_team", "season"], name: "index_player_opp_splits_on_player_opp_season", unique: true
    t.index ["player_id"], name: "index_player_opponent_splits_on_player_id"
    t.index ["season"], name: "index_player_opponent_splits_on_season"
  end

  create_table "player_season_stats", force: :cascade do |t|
    t.bigint "player_id", null: false
    t.string "season", null: false
    t.string "team_abbr"
    t.integer "gp"
    t.decimal "min", precision: 8, scale: 2
    t.decimal "pts", precision: 8, scale: 2
    t.decimal "reb", precision: 8, scale: 2
    t.decimal "ast", precision: 8, scale: 2
    t.decimal "stl", precision: 8, scale: 2
    t.decimal "blk", precision: 8, scale: 2
    t.decimal "tov", precision: 8, scale: 2
    t.decimal "fg_pct", precision: 6, scale: 3
    t.decimal "fg3_pct", precision: 6, scale: 3
    t.decimal "ft_pct", precision: 6, scale: 3
    t.jsonb "per_game_row", default: {}, null: false
    t.datetime "synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "fgm", precision: 8, scale: 2
    t.decimal "fga", precision: 8, scale: 2
    t.decimal "fg3m", precision: 8, scale: 2
    t.decimal "fg3a", precision: 8, scale: 2
    t.string "data_source"
    t.index ["player_id", "season"], name: "index_player_season_stats_on_player_id_and_season", unique: true
    t.index ["player_id"], name: "index_player_season_stats_on_player_id"
    t.index ["season"], name: "index_player_season_stats_on_season"
  end

  create_table "players", force: :cascade do |t|
    t.string "name"
    t.string "team"
    t.integer "nba_player_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "bdl_player_id"
    t.index ["bdl_player_id"], name: "index_players_on_bdl_player_id", unique: true, where: "(bdl_player_id IS NOT NULL)"
    t.index ["nba_player_id"], name: "index_players_on_nba_player_id", unique: true, where: "(nba_player_id IS NOT NULL)"
  end

  create_table "team_season_stats", force: :cascade do |t|
    t.string "season", null: false
    t.string "team_abbr", null: false
    t.string "team_name"
    t.integer "gp"
    t.integer "w"
    t.integer "l"
    t.decimal "min", precision: 8, scale: 2
    t.decimal "pts", precision: 8, scale: 2
    t.decimal "reb", precision: 8, scale: 2
    t.decimal "ast", precision: 8, scale: 2
    t.decimal "stl", precision: 8, scale: 2
    t.decimal "blk", precision: 8, scale: 2
    t.decimal "tov", precision: 8, scale: 2
    t.decimal "oreb", precision: 8, scale: 2
    t.decimal "dreb", precision: 8, scale: 2
    t.decimal "fgm", precision: 8, scale: 2
    t.decimal "fga", precision: 8, scale: 2
    t.decimal "fg_pct", precision: 6, scale: 3
    t.decimal "fg3m", precision: 8, scale: 2
    t.decimal "fg3a", precision: 8, scale: 2
    t.decimal "fg3_pct", precision: 6, scale: 3
    t.decimal "ftm", precision: 8, scale: 2
    t.decimal "fta", precision: 8, scale: 2
    t.decimal "ft_pct", precision: 6, scale: 3
    t.jsonb "per_game_row", default: {}, null: false
    t.datetime "synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.decimal "pace", precision: 8, scale: 3
    t.index ["season", "team_abbr"], name: "index_team_season_stats_on_season_and_abbr", unique: true
    t.index ["season"], name: "index_team_season_stats_on_season"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.string "role", default: "user", null: false
    t.string "api_token"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["api_token"], name: "index_users_on_api_token", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "ai_predictions", "games"
  add_foreign_key "ai_predictions", "players"
  add_foreign_key "alerts", "players"
  add_foreign_key "alerts", "users"
  add_foreign_key "bets", "games"
  add_foreign_key "bets", "players"
  add_foreign_key "bets", "users"
  add_foreign_key "comments", "games"
  add_foreign_key "comments", "users"
  add_foreign_key "odds_snapshots", "games"
  add_foreign_key "odds_snapshots", "players"
  add_foreign_key "player_game_stats", "games"
  add_foreign_key "player_game_stats", "players"
  add_foreign_key "player_opponent_splits", "players"
  add_foreign_key "player_season_stats", "players"
end
