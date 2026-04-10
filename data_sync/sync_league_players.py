#!/usr/bin/env python3
"""
Importa o elenco da temporada via nba_api (CommonAllPlayers) e grava em `players`.
Espelha o fluxo Ruby `NbaStats::LeaguePlayersSync`: upsert por nba_player_id + vínculo de órfãos (nome+time único).

Documentação do cliente: https://github.com/swar/nba_api
"""
from __future__ import annotations

import argparse
import os
import sys

from db import connect

try:
    from nba_api.stats.endpoints import commonallplayers
except ImportError:
    print("Instale nba_api: pip install nba_api", file=sys.stderr)
    sys.exit(1)


def main():
    p = argparse.ArgumentParser(description="Sync NBA roster (commonallplayers) into PostgreSQL players table.")
    p.add_argument("--season", default=None, help="Ex.: 2025-26 (default: env NBA_SEASON ou 2025-26)")
    p.add_argument("--no-link-orphans", action="store_true", help="Não preencher nba_player_id em jogadores existentes sem ID")
    args = p.parse_args()

    season = (args.season or os.environ.get("NBA_SEASON") or "2025-26").strip()

    print(f"Buscando elenco NBA (season={season}, IsOnlyCurrentSeason=1)...")
    raw = commonallplayers.CommonAllPlayers(
        season=season,
        is_only_current_season=1,
        timeout=90,
    ).get_dict()

    sets = raw.get("resultSets") or []
    cap = next((s for s in sets if s.get("name") == "CommonAllPlayers"), None)
    if not cap:
        print("Resposta sem CommonAllPlayers.", file=sys.stderr)
        sys.exit(1)

    headers = cap.get("headers") or []
    rows = cap.get("rowSet") or []

    def idx(name: str):
        try:
            return headers.index(name)
        except ValueError:
            return None

    i_pid = idx("PERSON_ID")
    i_name = idx("DISPLAY_FIRST_LAST")
    i_team = idx("TEAM_ABBREVIATION")
    if i_pid is None or i_name is None:
        print("Colunas PERSON_ID / DISPLAY_FIRST_LAST ausentes.", file=sys.stderr)
        sys.exit(1)

    name_team_map: dict[tuple[str, str], list[int]] = {}
    upserted = 0
    errors: list[str] = []

    conn = connect()
    try:
        for row in rows:
            try:
                nba_id = row[i_pid]
                if nba_id is None or nba_id == "":
                    continue
                nba_id = int(nba_id)
                name = str(row[i_name] or "").strip()
                if not name:
                    continue
                team_abbr = None
                if i_team is not None and row[i_team]:
                    team_abbr = str(row[i_team]).strip() or None

                with conn.cursor() as cur:
                    cur.execute("SELECT id, team FROM players WHERE nba_player_id = %s", (nba_id,))
                    existing = cur.fetchone()
                    if existing:
                        pid, cur_team = existing
                        new_team = team_abbr if team_abbr else cur_team
                        cur.execute(
                            """
                            UPDATE players SET name = %s, team = COALESCE(%s, team), updated_at = NOW()
                            WHERE id = %s
                            """,
                            (name, new_team, pid),
                        )
                    else:
                        cur.execute(
                            """
                            INSERT INTO players (name, team, nba_player_id, created_at, updated_at)
                            VALUES (%s, %s, %s, NOW(), NOW())
                            """,
                            (name, team_abbr, nba_id),
                        )
                    upserted += 1

                if team_abbr:
                    key = (name.lower(), team_abbr.upper())
                    if nba_id not in name_team_map.setdefault(key, []):
                        name_team_map[key].append(nba_id)
            except Exception as e:
                label = str(row[i_name] if i_name is not None else "") or f"id={row[i_pid]}"
                errors.append(f"{label}: {e}")

        linked = 0
        if not args.no_link_orphans and name_team_map:
            with conn.cursor() as cur:
                cur.execute(
                    """
                    SELECT id, name, team FROM players
                    WHERE nba_player_id IS NULL AND name IS NOT NULL AND team IS NOT NULL
                    """
                )
                orphans = cur.fetchall()
            for oid, oname, oteam in orphans:
                key = (str(oname).strip().lower(), str(oteam).strip().upper())
                ids = name_team_map.get(key) or []
                if len(ids) != 1:
                    continue
                nid = ids[0]
                try:
                    with conn.cursor() as cur:
                        cur.execute(
                            "SELECT 1 FROM players WHERE nba_player_id = %s AND id != %s",
                            (nid, oid),
                        )
                        if cur.fetchone():
                            continue
                        cur.execute(
                            "UPDATE players SET nba_player_id = %s, updated_at = NOW() WHERE id = %s",
                            (nid, oid),
                        )
                        linked += 1
                except Exception as e:
                    errors.append(f"link {oname}: {e}")

        conn.commit()
        print(f"Catálogo: {upserted} linha(s) processada(s) na API (upsert por nba_player_id).")
        print(f"Vínculos: {linked} jogador(es) sem ID receberam nba_player_id (nome+time único).")
        if errors:
            print(f"Erros ({len(errors)}), primeiros 20:")
            for e in errors[:20]:
                print(f"  {e}")
    finally:
        conn.close()


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"Erro: {e}", file=sys.stderr)
        sys.exit(1)
