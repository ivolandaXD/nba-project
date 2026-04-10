#!/usr/bin/env python3
"""
Importa game logs via nba_api (https://github.com/swar/nba_api) e grava em games + player_game_stats.
Útil quando stats.nba.com responde melhor a partir do Python do que do Ruby no seu ambiente.

Requer jogadores com nba_player_id e, de preferência, team (abreviação) preenchido.
"""
from __future__ import annotations

import argparse
import re
import sys
from datetime import datetime

from db import connect

try:
    from nba_api.stats.endpoints import playergamelog
except ImportError:
    print("Instale nba_api: pip install nba_api", file=sys.stderr)
    sys.exit(1)


def parse_minutes(raw):
    if raw is None or raw == "":
        return None
    s = str(raw)
    if ":" in s:
        a, b = s.split(":", 1)
        try:
            return float(a) + float(b) / 60.0
        except ValueError:
            return None
    try:
        return float(s)
    except ValueError:
        return None


def extract_opponent(matchup: str, team_abbr: str | None) -> str | None:
    parts = matchup.split()
    return parts[-1] if len(parts) >= 3 else None


def infer_teams(matchup: str, team_abbr: str | None, is_home: bool):
    parts = matchup.replace("@", " @ ").split()
    abbrs = [p for p in parts if re.match(r"^[A-Z]{2,3}$", p)]
    if not abbrs:
        return None, None
    opp = next((a for a in abbrs if a != team_abbr), abbrs[-1])
    ta = team_abbr or abbrs[0]
    if is_home:
        return ta, opp
    return opp, ta


def col_index(headers, name):
    try:
        return headers.index(name)
    except ValueError:
        return None


def sync_player(cur, player_id: int, nba_pid: int, team_abbr: str | None, season: str) -> int:
    raw = playergamelog.PlayerGameLog(player_id=str(nba_pid), season=season).get_dict()
    sets = raw.get("resultSets") or []
    log_set = next((s for s in sets if s.get("name") == "PlayerGameLog"), None)
    if not log_set:
        return 0
    headers = log_set.get("headers") or []
    rows = log_set.get("rowSet") or []
    idx = lambda n: col_index(headers, n)  # noqa: E731
    count = 0
    for row in rows:
        gi = idx("Game_ID")
        gd = idx("GAME_DATE")
        if gi is None or gd is None:
            continue
        game_id = row[gi]
        game_date_raw = row[gd]
        if not game_id or not game_date_raw:
            continue
        try:
            game_date = datetime.strptime(str(game_date_raw)[:10], "%Y-%m-%d").date()
        except ValueError:
            try:
                game_date = datetime.strptime(str(game_date_raw), "%b %d, %Y").date()
            except ValueError:
                continue
        matchup = str(row[idx("MATCHUP")] or "")
        is_home = "vs." in matchup
        opponent_team = extract_opponent(matchup, team_abbr)
        home_team, away_team = infer_teams(matchup, team_abbr, is_home)
        nba_game_id = str(game_id)

        cur.execute("SELECT id FROM games WHERE nba_game_id = %s", (nba_game_id,))
        gr = cur.fetchone()
        if gr:
            game_pk = gr[0]
        else:
            if not home_team or not away_team:
                home_team = home_team or "UNK"
                away_team = away_team or "UNK"
            cur.execute(
                """
                INSERT INTO games (game_date, home_team, away_team, status, nba_game_id, created_at, updated_at)
                VALUES (%s, %s, %s, %s, %s, NOW(), NOW())
                RETURNING id
                """,
                (game_date, home_team, away_team, "final", nba_game_id),
            )
            game_pk = cur.fetchone()[0]

        def v(name, default=None):
            i = idx(name)
            return row[i] if i is not None and i < len(row) else default

        minutes = parse_minutes(v("MIN"))
        cur.execute(
            """
            INSERT INTO player_game_stats (
              player_id, game_id, game_date, opponent_team, is_home,
              minutes, points, assists, rebounds, steals, blocks, turnovers,
              fgm, fga, fg_pct, three_pt_made, three_pt_attempted, three_pt_pct,
              ftm, fta, ft_pct, created_at, updated_at
            ) VALUES (
              %s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,NOW(),NOW()
            )
            ON CONFLICT (player_id, game_id) DO UPDATE SET
              game_date = EXCLUDED.game_date,
              opponent_team = EXCLUDED.opponent_team,
              is_home = EXCLUDED.is_home,
              minutes = EXCLUDED.minutes,
              points = EXCLUDED.points,
              assists = EXCLUDED.assists,
              rebounds = EXCLUDED.rebounds,
              steals = EXCLUDED.steals,
              blocks = EXCLUDED.blocks,
              turnovers = EXCLUDED.turnovers,
              fgm = EXCLUDED.fgm,
              fga = EXCLUDED.fga,
              fg_pct = EXCLUDED.fg_pct,
              three_pt_made = EXCLUDED.three_pt_made,
              three_pt_attempted = EXCLUDED.three_pt_attempted,
              three_pt_pct = EXCLUDED.three_pt_pct,
              ftm = EXCLUDED.ftm,
              fta = EXCLUDED.fta,
              ft_pct = EXCLUDED.ft_pct,
              updated_at = NOW()
            """,
            (
                player_id,
                game_pk,
                game_date,
                opponent_team,
                is_home,
                minutes,
                v("PTS"),
                v("AST"),
                v("REB"),
                v("STL"),
                v("BLK"),
                v("TOV"),
                v("FGM"),
                v("FGA"),
                v("FG_PCT"),
                v("FG3M"),
                v("FG3A"),
                v("FG3_PCT"),
                v("FTM"),
                v("FTA"),
                v("FT_PCT"),
            ),
        )
        count += 1
    return count


def main():
    p = argparse.ArgumentParser(description="Sync player game logs via nba_api into PostgreSQL.")
    p.add_argument("--season", default="2025-26", help="Ex.: 2025-26")
    p.add_argument("--limit", type=int, default=3, help="Máximo de jogadores com nba_player_id")
    args = p.parse_args()

    conn = connect()
    try:
        with conn.cursor() as cur:
            cur.execute(
                """
                SELECT id, nba_player_id, team FROM players
                WHERE nba_player_id IS NOT NULL
                ORDER BY id
                LIMIT %s
                """,
                (args.limit,),
            )
            players = cur.fetchall()
        total_stats = 0
        for pid, nba_pid, team in players:
            with conn.cursor() as cur:
                n = sync_player(cur, pid, nba_pid, team, args.season)
                conn.commit()
            print(f"player id={pid} nba_player_id={nba_pid}: {n} linha(s)")
            total_stats += n
        print(f"OK: {total_stats} linha(s) de game log no total.")
    finally:
        conn.close()


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"Erro: {e}", file=sys.stderr)
        sys.exit(1)
