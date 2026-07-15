#!/usr/bin/env bash
# Builds all service jars (single Maven reactor) then the compose images.
set -euo pipefail
cd "$(dirname "$0")"

mvn -f ../pom.xml clean package -DskipTests
docker compose build
