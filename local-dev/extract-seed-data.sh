#!/usr/bin/env bash
# Extracts seed data + service config from a RUNNING local all-in-one stack.
# Read-only with respect to the AIO; writes only ./seed and ./config here.
set -euo pipefail
cd "$(dirname "$0")"

: "${DOCKER_CONFIG_DIR:?Set DOCKER_CONFIG_DIR to your local all-in-one directory}"

for c in picsure-db dictionary-db; do
  if [ "$(docker inspect -f '{{.State.Running}}' "$c" 2>/dev/null)" != "true" ]; then
    echo "ERROR: AIO container '$c' is not running — start the all-in-one first." >&2
    exit 1
  fi
done

rm -rf seed config
mkdir -p seed/mysql seed/postgres seed/hpds config/psama config/dictionary

echo "==> Dumping MySQL databases picsure + auth"
docker exec picsure-db sh -c \
  'mysqldump -uroot -p"$MYSQL_ROOT_PASSWORD" --databases picsure auth --single-transaction --routines --triggers' \
  > seed/mysql/10-data.sql

echo "==> Generating MySQL application users"
AUTH_PW=$(grep -E '^DATASOURCE_PASSWORD=' "$DOCKER_CONFIG_DIR/psama/psama.env" | head -1 | cut -d= -f2-)
PICSURE_PW=$(grep -E '^SPRING_DATASOURCE_PASSWORD=' "$DOCKER_CONFIG_DIR/operations/operations.env" | head -1 | cut -d= -f2-)
[ -n "$AUTH_PW" ] || { echo "ERROR: DATASOURCE_PASSWORD not found in psama.env" >&2; exit 1; }
[ -n "$PICSURE_PW" ] || { echo "ERROR: SPRING_DATASOURCE_PASSWORD not found in operations.env" >&2; exit 1; }
# Escape for use inside MySQL single-quoted string literals: backslashes first, then quotes.
sql_escape() { printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e "s/'/\\\\'/g"; }
AUTH_PW_SQL=$(sql_escape "$AUTH_PW")
PICSURE_PW_SQL=$(sql_escape "$PICSURE_PW")
cat > seed/mysql/20-users.sql <<SQL
CREATE USER IF NOT EXISTS 'auth'@'%' IDENTIFIED BY '${AUTH_PW_SQL}';
GRANT ALL PRIVILEGES ON auth.* TO 'auth'@'%';
CREATE USER IF NOT EXISTS 'picsure'@'%' IDENTIFIED BY '${PICSURE_PW_SQL}';
GRANT ALL PRIVILEGES ON picsure.* TO 'picsure'@'%';
FLUSH PRIVILEGES;
SQL

echo "==> Dumping Postgres database dictionary"
docker exec dictionary-db pg_dump -U picsure --no-owner dictionary > seed/postgres/10-dictionary.sql

echo "==> Copying HPDS data files"
rsync -a --exclude 'hpds.env' "$DOCKER_CONFIG_DIR/hpds/" seed/hpds/

echo "==> Copying service env files"
cp "$DOCKER_CONFIG_DIR/gateway/gateway.env"              config/gateway.env
cp "$DOCKER_CONFIG_DIR/query/query.env"                  config/query.env
cp "$DOCKER_CONFIG_DIR/visualization/visualization.env"  config/visualization.env
cp "$DOCKER_CONFIG_DIR/operations/operations.env"        config/operations.env
cp "$DOCKER_CONFIG_DIR/logging/logging.env"              config/logging.env
cp "$DOCKER_CONFIG_DIR/hpds/hpds.env"                    config/hpds.env
cp "$DOCKER_CONFIG_DIR/dictionary/dictionary.env"        config/dictionary.env
cp "$DOCKER_CONFIG_DIR/psama/psama.env"                  config/psama.env

echo "==> Copying PSAMA truststore + email templates"
cp "$DOCKER_CONFIG_DIR/psama/application.truststore" config/psama/application.truststore
cp -R "$DOCKER_CONFIG_DIR/psama/emailTemplates"      config/psama/emailTemplates

echo "==> Copying dictionary-dump application.properties"
if [ -f "$DOCKER_CONFIG_DIR/dictionary/dump/application.properties" ]; then
  cp "$DOCKER_CONFIG_DIR/dictionary/dump/application.properties" config/dictionary/application.properties
else
  echo "WARN: no real application.properties at $DOCKER_CONFIG_DIR/dictionary/dump/" >&2
  echo "WARN: (empty bind-mount directory artifact seen on some AIO installs) — creating empty placeholder." >&2
  : > config/dictionary/application.properties
fi

echo "Done. seed/ and config/ are populated (gitignored — never commit them)."
