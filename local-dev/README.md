# PIC-SURE Local Dev Stack

Runs the core PIC-SURE API locally with docker compose, built from this repo's
source and seeded with data extracted from a local all-in-one (AIO) install.

## Quick start

1. `export DOCKER_CONFIG_DIR=/path/to/local-all-in-one` (AIO must be running)
2. `./extract-seed-data.sh`   # one-time: dump DBs + copy config from the AIO
3. `./build.sh`               # mvn package + docker compose build
4. `docker compose up -d`
5. `curl -s http://localhost:8081/actuator/health`

(Full docs completed in later tasks: services, frontend attach, smoke tests,
re-seeding, troubleshooting.)
