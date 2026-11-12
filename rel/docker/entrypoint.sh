#!/bin/sh
# Démarrage du conteneur Blind Mix.
#
# Tout ce qui n'est pas fourni par l'environnement est pris en charge ici, pour qu'un simple
#   docker run -p 4000:4000 -v blindmix:/data ghcr.io/fyndir/blind_mix
# suffise :
#   * SECRET_KEY_BASE absent : générée une fois, conservée dans /data ;
#   * DATABASE_URL absent    : PostgreSQL embarqué, données dans /data/postgres,
#                              accessible seulement depuis le conteneur.
# Sans service mail (MAIL_PROVIDER), l'app passe d'elle-même en connexion par mot de passe.
set -eu

DATA_DIR="${DATA_DIR:-/data}"
APP_PID=""
PG_BIN=""
PGDATA=""

# Sur stderr : les fonctions appelées dans $(...) ne doivent écrire sur stdout que leur résultat.
log() { echo "[blind-mix] $*" >&2; }

# Lance une commande sous l'utilisateur `nobody` (l'app n'a pas besoin d'être root).
as_app() { setpriv --reuid=nobody --regid=nogroup --clear-groups -- "$@"; }
as_postgres() { setpriv --reuid=postgres --regid=postgres --init-groups -- "$@"; }

# Chaîne aléatoire alphanumérique (utilisable telle quelle dans une URL).
random_string() { head -c 96 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c "$1"; }

# Lit un secret dans un fichier de /data, en le créant au premier démarrage.
persistent_secret() {
  file="$DATA_DIR/$1"
  if [ ! -s "$file" ]; then
    random_string "$2" > "$file"
    chmod 600 "$file"
    log "$1 généré dans $file"
  fi
  cat "$file"
}

stop_postgres() {
  if [ -n "$PG_BIN" ]; then
    log "arrêt de PostgreSQL"
    as_postgres "$PG_BIN/pg_ctl" -D "$PGDATA" -m fast -w stop >/dev/null || true
    PG_BIN=""
  fi
}

shutdown() {
  if [ -n "$APP_PID" ]; then
    kill -TERM "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
  fi
  stop_postgres
  exit 0
}
trap shutdown TERM INT

mkdir -p "$DATA_DIR"

# --- Clé secrète ---------------------------------------------------------------
if [ -z "${SECRET_KEY_BASE:-}" ]; then
  SECRET_KEY_BASE="$(persistent_secret secret_key_base 64)"
  export SECRET_KEY_BASE
fi

# --- Base de données -------------------------------------------------------------
if [ -z "${DATABASE_URL:-}" ]; then
  log "DATABASE_URL absent : PostgreSQL embarqué ($DATA_DIR/postgres)"
  PG_BIN="$(ls -d /usr/lib/postgresql/*/bin | sort -V | tail -n 1)"
  PGDATA="$DATA_DIR/postgres"
  password="$(persistent_secret postgres_password 32)"

  mkdir -p "$PGDATA" /run/postgresql
  chown postgres:postgres "$PGDATA" /run/postgresql
  chmod 700 "$PGDATA"

  if [ ! -s "$PGDATA/PG_VERSION" ]; then
    log "initialisation de la base"
    pwfile="$(mktemp)"
    printf '%s' "$password" > "$pwfile"
    chown postgres "$pwfile"
    as_postgres "$PG_BIN/initdb" -D "$PGDATA" -U postgres --pwfile="$pwfile" \
      --auth=scram-sha-256 -E UTF8 --locale=C.UTF-8 >/dev/null
    rm -f "$pwfile"
  fi

  as_postgres "$PG_BIN/pg_ctl" -D "$PGDATA" -w -l "$PGDATA/server.log" \
    -o "-c listen_addresses=127.0.0.1 -c unix_socket_directories=/run/postgresql" start >/dev/null

  export PGPASSWORD="$password"
  if ! "$PG_BIN/psql" -h 127.0.0.1 -U postgres -tAc \
    "SELECT 1 FROM pg_database WHERE datname = 'blind_mix'" | grep -q 1; then
    "$PG_BIN/createdb" -h 127.0.0.1 -U postgres blind_mix
  fi
  unset PGPASSWORD

  DATABASE_URL="ecto://postgres:${password}@127.0.0.1/blind_mix"
  export DATABASE_URL
fi

if [ -z "${MAIL_PROVIDER:-}" ]; then
  log "MAIL_PROVIDER absent : inscription et connexion par mot de passe"
fi

# --- Application -----------------------------------------------------------------
log "migrations"
as_app /app/bin/migrate

log "démarrage du serveur"
as_app /app/bin/server &
APP_PID=$!

status=0
wait "$APP_PID" || status=$?
APP_PID=""
stop_postgres
exit "$status"
