#!/usr/bin/env bash
# Builds all service jars (single Maven reactor) then the compose images.
set -euo pipefail
cd "$(dirname "$0")"
script_dir="$(pwd)"

# Activate the JDK pinned by the repo's .sdkmanrc (java=25.x) when SDKMAN is
# available, so the build works from a fresh shell whose default JDK differs.
# sdkman-init.sh is not `set -u`-clean, and `sdk env` can return nonzero on
# some setups; if activation is skipped or fails, Maven's enforcer plugin
# still fails loudly on a wrong JDK.
if [[ -s "${SDKMAN_DIR:-$HOME/.sdkman}/bin/sdkman-init.sh" && -f ../.sdkmanrc ]]; then
  set +u
  # shellcheck disable=SC1091
  source "${SDKMAN_DIR:-$HOME/.sdkman}/bin/sdkman-init.sh"
  cd ..
  sdk env || true
  cd "$script_dir"
  set -u
fi

mvn -f ../pom.xml clean package -DskipTests
docker compose build
