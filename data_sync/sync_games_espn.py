#!/usr/bin/env python3
"""
Sincroniza a grade NBA do dia a partir da API pública da ESPN.
Documentação comunitária: https://gist.github.com/akeaswaran/b48b02f1c94f873c6655e7129910fc3b

Grava na tabela `games` com nba_game_id = espn-<event_id> (igual ao Espn::ScoreboardSync no Rails).
"""
from __future__ import annotations

import argparse
import json
import sys
from datetime import date, datetime
from zoneinfo import ZoneInfo

import requests

from db import connect

ESPN_SCOREBOARD = (
    "https://site.api.espn.com/apis/site/v2/sports/basketball/nba/scoreboard"
)


def et_today() -> date:
    return datetime.now(ZoneInfo("America/New_York")).date()


def fetch_scoreboard(ymd: str) -> dict:
    r = requests.get(
        ESPN_SCOREBOARD,
        params={"dates": ymd},
        headers={"User-Agent": "Mozilla/5.0 (compatible; nba-data-sync/1.0)"},
        timeout=(15, 45),
    )
    r.raise_for_status()
    return r.json()


def parse_game_date(iso: str | None, fallback: date) -> date:
    if not iso:
        return fallback
    try:
        # ISO com Z: ancorar em ET como no Rails
        dt = datetime.fromisoformat(iso.replace("Z", "+00:00"))
        return dt.astimezone(ZoneInfo("America/New_York")).date()
    except (ValueError, TypeError):
        return fallback


def upsert_games(conn, target_date: date) -> int:
    ymd = target_date.strftime("%Y%m%d")
    data = fetch_scoreboard(ymd)
    events = data.get("events") or []
    count = 0
    with conn.cursor() as cur:
        for event in events:
            comp = (event.get("competitions") or [None])[0]
            if not comp:
                continue
            competitors = comp.get("competitors") or []
            home = next((c for c in competitors if c.get("homeAway") == "home"), None)
            away = next((c for c in competitors if c.get("homeAway") == "away"), None)
            if not home or not away:
                continue
            home_abbr = (home.get("team") or {}).get("abbreviation") or ""
            away_abbr = (away.get("team") or {}).get("abbreviation") or ""
            if not home_abbr or not away_abbr:
                continue
            status = (
                (comp.get("status") or {}).get("type") or {}
            ).get("shortDetail") or (
                (comp.get("status") or {}).get("type") or {}
            ).get("detail") or (
                (event.get("status") or {}).get("type") or {}
            ).get("shortDetail") or "scheduled"
            espn_id = str(event.get("id") or "")
            if not espn_id:
                continue
            nba_game_id = f"espn-{espn_id}"
            game_date = parse_game_date(event.get("date"), target_date)
            st = str(status).strip() or "scheduled"
            cur.execute("SELECT id FROM games WHERE nba_game_id = %s", (nba_game_id,))
            row = cur.fetchone()
            if row:
                cur.execute(
                    """
                    UPDATE games
                    SET game_date = %s, home_team = %s, away_team = %s, status = %s, updated_at = NOW()
                    WHERE id = %s
                    """,
                    (game_date, home_abbr, away_abbr, st, row[0]),
                )
            else:
                cur.execute(
                    """
                    INSERT INTO games (game_date, home_team, away_team, status, nba_game_id, created_at, updated_at)
                    VALUES (%s, %s, %s, %s, %s, NOW(), NOW())
                    """,
                    (game_date, home_abbr, away_abbr, st, nba_game_id),
                )
            count += 1
    conn.commit()
    return count


def main() -> None:
    p = argparse.ArgumentParser(description="Sync NBA scoreboard from ESPN into PostgreSQL.")
    p.add_argument(
        "--date",
        type=str,
        help="Data do jogo em ET (YYYY-MM-DD). Padrão: hoje em America/New_York.",
    )
    p.add_argument("--dry-run", action="store_true", help="Só baixa JSON e imprime quantidade de eventos.")
    args = p.parse_args()
    if args.date:
        target = date.fromisoformat(args.date)
    else:
        target = et_today()

    if args.dry_run:
        ymd = target.strftime("%Y%m%d")
        data = fetch_scoreboard(ymd)
        n = len(data.get("events") or [])
        print(json.dumps({"date_et": str(target), "events": n}, indent=2))
        return

    conn = connect()
    try:
        n = upsert_games(conn, target)
        print(f"OK: {n} jogo(s) para {target} (ET) gravados/atualizados.")
    finally:
        conn.close()


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"Erro: {e}", file=sys.stderr)
        sys.exit(1)
