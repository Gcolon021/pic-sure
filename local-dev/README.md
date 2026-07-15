# PIC-SURE Local Dev Stack

Runs the core PIC-SURE API locally with docker compose, built from this repo's
source and seeded with data extracted from a local all-in-one (AIO) install.

## Quick start

1. `export DOCKER_CONFIG_DIR=/path/to/local-all-in-one` (AIO must be running)
2. `./extract-seed-data.sh`   # one-time: dump DBs + copy config from the AIO
3. `./build.sh`               # mvn package + docker compose build
4. `docker compose up -d`
5. `curl -s http://localhost:8081/actuator/health`

## What you get

| Service | Built from | Host port |
|---|---|---|
| gateway | services/pic-sure-gateway | 8081 |
| psama | services/pic-sure-auth-microapp | 8091 |
| api-proxy (nginx, /picsure + /psama rewrites) | — | 8082 |
| MySQL 8 (picsure + auth, seeded) | — | 3307 |
| Postgres 16 (dictionary, seeded) | — | 5433 |
| hpds, hpds-query-service, visualization, dictionary-api, dictionary-dump, operations, logging | this repo (dump: upstream image) | internal only |

Coexists with a running all-in-one: separate `picsure-local` network/volumes,
no fixed container names, non-conflicting host ports.

## Prerequisites

- Docker Desktop (HPDS defaults to `-Xmx4g` in this stack — `extract-seed-data.sh`
  lowers the AIO's `-Xmx16g` at copy time so it fits alongside a coexisting AIO
  on a laptop-class Docker VM; raise it by editing `config/hpds.env` after
  extraction, or set `LOCAL_HPDS_XMX` before running the script, if you have
  memory to spare)
- Maven + JDK matching the repo toolchain (`build.sh` auto-activates the
  repo's pinned JDK via SDKMAN when available; otherwise install JDK 25
  yourself)
- A running local all-in-one (only needed once, for extraction)

## Seeding / re-seeding

`./extract-seed-data.sh` dumps the AIO's MySQL (picsure + auth) and Postgres
(dictionary) databases and copies HPDS data + per-service env files into
seed/ and config/ (both gitignored — they contain real data and secrets).
To re-seed later: re-run the script, then `docker compose down -v && docker compose up -d`.

## Smoke tests

    curl http://localhost:8081/actuator/health              # gateway aggregate health
    curl http://localhost:8091/auth/actuator/health          # psama
    curl http://localhost:8082/picsure/system/status         # via api-proxy (frontend path shape)

Bruno: `cd ../integration-tests/bruno && bru run 00-smoke --env compose-local`
(tokens in integration-tests/bruno/.env; AIO-issued tokens remain valid because
the auth DB and PSAMA secrets are carried over). The full Bruno smoke suite
currently exists only on the `feature/bruno-integration-suite` branch; the
`compose-local` environment for it is committed here and already works with
that branch's suite.

## Running a frontend against this stack

The `picsure-local` network is attachable and resolves `gateway:8080` /
`psama:8090` exactly like the AIO's network, so an unmodified frontend works.
Verified working command (the AIO frontend image mounts only vhosts config,
cert, and an env file — it does not mount a `settings.json`; this build reads
its `VITE_*` settings from the env file instead):

    docker run -d --rm --name picsure-local-frontend --network picsure-local -p 8443:443 \
      --env-file "$DOCKER_CONFIG_DIR/httpd/httpd.env" \
      -v "$DOCKER_CONFIG_DIR/httpd/httpd-vhosts.conf":/usr/local/apache2/conf/extra/httpd-vhosts.conf:ro \
      -v "$DOCKER_CONFIG_DIR/httpd/cert":/usr/local/apache2/cert:ro \
      hms-dbmi/pic-sure-frontend:LATEST

    curl -sk https://localhost:8443/picsure/system/status   # -> RUNNING
    curl -sk https://localhost:8443/psama/actuator/health    # -> {"status":"UP",...}

    docker stop picsure-local-frontend

If your image/config still references a `picsureui_settings.json` mount,
inspect the AIO's actual running container to get exact source paths:

    docker inspect httpd --format '{{range .Mounts}}{{.Source}} -> {{.Destination}}{{"\n"}}{{end}}'

Note that `/` and `/psamaui/login` are served by a `node` process inside the
frontend container (proxied to `httpd:3000`) and may not fully render without
the rest of the AIO's frontend build context — that's expected and does not
indicate a problem with this stack. What matters is that `/picsure/*` and
`/psama/*` proxy correctly to gateway/psama on `picsure-local`, which they do.

Or in a frontend docker-compose:

    networks:
      picsure-local:
        external: true

Note: use a host port other than 443 if the AIO is also running. For Auth0
interactive login, add your local frontend URL (e.g. https://localhost:8443)
to the Auth0 application's allowed callback URLs; Open Access and
token-based API calls need no Auth0 changes.

## Troubleshooting

- **psama / pic-sure-logging healthchecks use `127.0.0.1`, not `localhost`**:
  the busybox `wget` used in these containers' healthchecks resolves
  `localhost` to `::1` (IPv6), but the services only listen on IPv4, which
  makes the healthcheck fail with "connection refused" even though the
  service is up. The compose file's healthcheck commands already use
  `127.0.0.1` for this reason — keep that if you touch them.
- **HPDS OOM on boot**: if HPDS is seeded from an AIO with a large heap
  requirement, `extract-seed-data.sh` rewrites `-Xmx16g` down to `-Xmx4g` in
  `config/hpds.env` at copy time so it fits alongside a coexisting AIO on a
  laptop Docker VM. If you have memory to spare, raise it by editing
  `config/hpds.env` (or set `LOCAL_HPDS_XMX` before extracting).
- **Port already in use**: this stack uses 8081/8091/8082/3307/5433 by
  default to avoid clashing with an AIO on its usual ports; override with the
  `*_HOST_PORT` env vars in docker-compose.yml if you still collide with
  something else on your machine.
- **Frontend container port 8443**: pick any free host port; 443 is likely
  taken by a running AIO's `httpd` container.
