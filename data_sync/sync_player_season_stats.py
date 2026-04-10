#!/usr/bin/env python3
"""
Importa médias por jogo da temporada regular (playercareerstats, PerMode=PerGame) para `player_season_stats`.
Alinhado ao Ruby `NbaStats::PlayerSeasonStatsSync`.

Cliente: https://github.com/swar/nba_api
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
from decimal import Decimal
from typing import Any

from db import connect

try:
    from nba_api.stats.endpoints import playercareerstats
except ImportError:
    print("Instale nba_api: pip install nba_api", file=sys.stderr)
    sys.exit(1)


def normalize_season_id(val: Any) -> str:
    return str(val).strip().replace(" ", "")


def row_to_hash(headers: list[str], row: list[Any]) -> dict[str, Any]:
    out: dict[str, Any] = {}
    for i, name in enumerate(headers):
        if i < len(row):
            out[name] = row[i]
    return out


def extract_season_row(body: dict, season: str) -> dict[str, Any] | None:
    want = normalize_season_id(season)
    for target_set in body.get("resultSets") or []:
        headers = target_set.get("headers") or []
        if "SEASON_ID" not in headers:
            continue
        idx_season = headers.index("SEASON_ID")
        rows = target_set.get("rowSet") or []
        candidates = [r for r in rows if normalize_season_id(r[idx_season]) == want]
        if not candidates:
            continue
        if len(candidates) > 1:
            h_gp = headers.index("GP") if "GP" in headers else None
            if h_gp is not None:
                candidates = [max(candidates, key=lambda r: int(r[h_gp] or 0))]
            else:
                candidates = [candidates[0]]
        return row_to_hash(headers, candidates[0])
    return None


def pick_str(h: dict[str, Any], keys: list[str]) -> str | None:
    for k in keys:
        if k in h and h[k] is not None and str(h[k]).strip() != "":
            return str(h[k]).strip()
    return None


def pick_int(h: dict[str, Any], keys: list[str]) -> int | None:
    for k in keys:
        if k in h and h[k] is not None and h[k] != "":
            try:
                return int(h[k])
            except (TypeError, ValueError):
                continue
    return None


def pick_dec(h: dict[str, Any], keys: list[str]) -> Decimal | None:
    for k in keys:
        if k not in h:
            continue
        v = h[k]
        if v is None or v == "":
            return None
        try:
            return Decimal(str(v)).quantize(Decimal("0.001"))
        except Exception:
            continue
    return None


def sync_one(cur, player_pk: int, nba_pid: int, season: str) -> tuple[bool, str | None]:
    raw = playercareerstats.PlayerCareerStats(
        player_id=str(nba_pid),
        per_mode36="PerGame",
        timeout=90,
    ).get_dict()
    if not isinstance(raw, dict):
        return False, "JSON inválido"
    row_hash = extract_season_row(raw, season)
    if not row_hash:
        return False, f"temporada {season} não encontrada na NBA"

    team_abbr = pick_str(row_hash, ["TEAM_ABBREVIATION", "TEAM_ABBREV", "TEAM"])
    gp = pick_int(row_hash, ["GP"])
    min_v = pick_dec(row_hash, ["MIN"])
    pts = pick_dec(row_hash, ["PTS"])
    reb = pick_dec(row_hash, ["REB", "REBOUNDS"])
    ast = pick_dec(row_hash, ["AST"])
    stl = pick_dec(row_hash, ["STL"])
    blk = pick_dec(row_hash, ["BLK"])
    tov = pick_dec(row_hash, ["TOV"])
    fgm = pick_dec(row_hash, ["FGM"])
    fga = pick_dec(row_hash, ["FGA"])
    fg3m = pick_dec(row_hash, ["FG3M"])
    fg3a = pick_dec(row_hash, ["FG3A"])
    fg_pct = pick_dec(row_hash, ["FG_PCT"])
    fg3_pct = pick_dec(row_hash, ["FG3_PCT"])
    ft_pct = pick_dec(row_hash, ["FT_PCT"])
    per_game_json = json.dumps(row_hash, default=str)

    cur.execute(
        """
        INSERT INTO player_season_stats (
          player_id, season, team_abbr, gp, min, pts, reb, ast, stl, blk, tov,
          fgm, fga, fg3m, fg3a, fg_pct, fg3_pct, ft_pct, per_game_row, synced_at, created_at, updated_at
        ) VALUES (
          %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s, %s::jsonb, NOW(), NOW(), NOW()
        )
        ON CONFLICT (player_id, season) DO UPDATE SET
          team_abbr = EXCLUDED.team_abbr,
          gp = EXCLUDED.gp,
          min = EXCLUDED.min,
          pts = EXCLUDED.pts,
          reb = EXCLUDED.reb,
          ast = EXCLUDED.ast,
          stl = EXCLUDED.stl,
          blk = EXCLUDED.blk,
          tov = EXCLUDED.tov,
          fgm = EXCLUDED.fgm,
          fga = EXCLUDED.fga,
          fg3m = EXCLUDED.fg3m,
          fg3a = EXCLUDED.fg3a,
          fg_pct = EXCLUDED.fg_pct,
          fg3_pct = EXCLUDED.fg3_pct,
          ft_pct = EXCLUDED.ft_pct,
          per_game_row = EXCLUDED.per_game_row,
          synced_at = NOW(),
          updated_at = NOW()
        """,
        (
            player_pk,
            season,
            team_abbr,
            gp,
            min_v,
            pts,
            reb,
            ast,
            stl,
            blk,
            tov,
            fgm,
            fga,
            fg3m,
            fg3a,
            fg_pct,
            fg3_pct,
            ft_pct,
            per_game_json,
        ),
    )
    return True, None


def main():
    p = argparse.ArgumentParser(description="Sync player_season_stats via nba_api (playercareerstats PerGame).")
    p.add_argument("--season", default=None, help="Ex.: 2025-26 (default: env NBA_SEASON ou 2025-26)")
    p.add_argument("--limit", type=int, default=None, help="Máximo de jogadores (default: todos com nba_player_id)")
    p.add_argument(
        "--delay",
        type=float,
        default=None,
        help="Segundos entre chamadas à API (default: env NBA_SEASON_SYNC_DELAY_SEC ou 0.35)",
    )
    args = p.parse_args()

    season = (args.season or os.environ.get("NBA_SEASON") or "2025-26").strip()
    delay = args.delay
    if delay is None:
        delay = float(os.environ.get("NBA_SEASON_SYNC_DELAY_SEC", "0.35"))

    conn = connect()
    synced = 0
    errors: list[str] = []
    try:
        with conn.cursor() as cur:
            q = """
                SELECT id, nba_player_id, name FROM players
                WHERE nba_player_id IS NOT NULL
                ORDER BY id
            """
            if args.limit is not None:
                q += " LIMIT %s"
                cur.execute(q, (args.limit,))
            else:
                cur.execute(q)
            players = cur.fetchall()

        if not players:
            print("Nenhum jogador com nba_player_id. Rode: python sync_league_players.py")
            return

        print(f"Temporada: {season} · jogadores: {len(players)} · delay={delay}s")

        for player_pk, nba_pid, name in players:
            try:
                with conn.cursor() as cur:
                    ok, err = sync_one(cur, player_pk, int(nba_pid), season)
                    if ok:
                        conn.commit()
                        synced += 1
                        print(f" OK id={player_pk} {name}")
                    else:
                        conn.rollback()
                        errors.append(f"{name}: {err}")
                        print(f"  skip id={player_pk} {name}: {err}")
            except Exception as e:
                conn.rollback()
                errors.append(f"{name}: {e}")
                print(f"  erro id={player_pk} {name}: {e}")
            if delay > 0:
                time.sleep(delay)

        print(f"Concluído: {synced} jogador(es) com player_season_stats atualizado(s).")
        if errors:
            print(f"Avisos/erros: {len(errors)} (mostrando até 30)")
            for e in errors[:30]:
                print(f"  {e}")
    finally:
        conn.close()


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"Erro: {e}", file=sys.stderr)
        sys.exit(1)
