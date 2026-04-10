# Sincronização de dados (Python) — mesmo PostgreSQL do Rails

Scripts opcionais para quem prefere **cron**, **CI** ou ambiente onde `stats.nba.com` responde melhor via [nba_api](https://github.com/swar/nba_api) (Python) do que pelo app Ruby.

## Referências

- **ESPN (grade / placares):** endpoints não oficiais documentados na comunidade — [ESPN hidden API (gist)](https://gist.github.com/akeaswaran/b48b02f1c94f873c6655e7129910fc3b). NBA: `.../basketball/nba/scoreboard` com `?dates=YYYYMMDD`.
- **NBA.com (game logs etc.):** [swar/nba_api](https://github.com/swar/nba_api) — cliente Python que chama as mesmas APIs do site da NBA.

O app Rails já usa **ESPN por padrão** para “Atualizar jogos” (`NBA_SCOREBOARD_PROVIDER=espn`). Estes scripts servem para **espelhar** ou **enriquecer** dados fora do processo web.

## Setup

```bash
cd data_sync
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
cp .env.example .env
```

`DATABASE_URL` deve apontar para o **mesmo** banco do `nba-project` (ex.: `postgres://localhost/nba-project_development`).

## Fluxo recomendado (dados no banco → views Rails)

Ordem típica usando [swar/nba_api](https://github.com/swar/nba_api) e o **mesmo** PostgreSQL do app:

1. **`sync_league_players.py`** — `CommonAllPlayers`: preenche `players` com `nba_player_id`, nome e time; tenta vincular registros antigos sem ID (nome + abreviação do time únicos).
2. **`sync_player_season_stats.py`** — `PlayerCareerStats` (PerGame): grava/atualiza `player_season_stats` (tela **Estatísticas da temporada**).
3. **`sync_player_gamelogs.py`** — `PlayerGameLog`: preenche `games` + `player_game_stats` (opcional, mais pesado).
4. **`sync_games_espn.py`** — grade ESPN (alinhada ao provider padrão do Rails), se quiser jogos sem depender da NBA.

```bash
cd data_sync
source .venv/bin/activate   # se usar venv

#1) Elenco + IDs (obrigatório para o passo 2 funcionar em massa)
python sync_league_players.py --season 2025-26

# 2) Médias da temporada (todos com nba_player_id; use --limit para teste)
python sync_player_season_stats.py --season 2025-26
python sync_player_season_stats.py --season 2025-26 --limit 25

# 3) Game logs (exemplo)
python sync_player_gamelogs.py --limit 10 --season 2025-26

# Grade do dia (ET) — mesmo formato que o Rails grava (nba_game_id = espn-<id>)
python sync_games_espn.py
python sync_games_espn.py --date 2024-12-25
```

Variáveis úteis no `.env`: `DATABASE_URL` (obrigatório), `NBA_SEASON`, `NBA_SEASON_SYNC_DELAY_SEC` (espaça chamadas à stats.nba.com).

Equivalente no Rails (sem Python): `bin/rails nba:sync_league_players`, `bin/rails nba:sync_season_stats`, `bin/rails nba:sync_season_full`.

**Fallback no Rails (NBA → balldontlie.io):** `NbaStats::PlayerGameLogImporter` e `NbaStats::PlayerSeasonStatsSync` tentam primeiro **stats.nba.com**; se falhar ou vier vazio, usam **api.balldontlie.io** (timeouts curtos + retry). Linhas em `player_game_stats` / `player_season_stats` guardam `data_source` (`nba` ou `balldontlie`). Dados já gravados com fonte NBA **não** são sobrescritos pelo fallback.

### Dados agregados para comparações / IA (Rails)

No app Ruby (após `db:migrate`):

- `bin/rails nba:sync_team_season_stats` — médias **por time** na liga (PTS, REB, AST, FGM/FGA, 3PM/3PA, etc.) via `leaguedashteamstats` → tabela `team_season_stats`.
- `bin/rails nba:rebuild_player_opponent_splits` — médias **jogador × adversário** a partir de `player_game_stats` (intervalo `Nba::Season.date_range_for`) → `player_opponent_splits`.
- `bin/rails nba:sync_context_for_ai` — executa os dois acima.

A sincronização da grade **ESPN** passa a gravar também `games.meta` (jsonb, ex.: odds/brindes) e, quando a API expuser, `home_win_prob` / `away_win_prob` (0–1). Probabilidade do **NBA.com** por jogo pode ser acrescentada depois com outro endpoint (ex.: win probability) usando o `nba_game_id` numérico da NBA.

## Repo separado

Você pode copiar só a pasta `data_sync/` para um repositório novo (ex. `nba-data-sync`), manter este README e apontar `DATABASE_URL` para produção/homologação.

## Termos de uso

ESPN e NBA.com têm termos próprios para uso dos dados; use apenas em contexto pessoal/projeto interno conforme permitido.
