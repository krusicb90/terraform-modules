#!/usr/bin/env bash
# Build a Lambda layer with the database driver that sql_checks need.
#
# Usage:
#   scripts/build-driver-layer.sh postgres   # pg8000
#   scripts/build-driver-layer.sh mysql      # PyMySQL
#
# Both drivers are pure Python, so the layer works on arm64 and x86_64.
# Publish the result with:
#   aws lambda publish-layer-version --layer-name restore-drill-driver \
#     --zip-file fileb://build/driver-layer-<engine>.zip \
#     --compatible-runtimes python3.13

set -euo pipefail

engine="${1:-}"
case "$engine" in
  postgres) package="pg8000==1.31.6" ;;
  mysql) package="PyMySQL==1.2.4" ;;
  *)
    echo "usage: $0 postgres|mysql" >&2
    exit 2
    ;;
esac

module_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="$module_dir/build"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

mkdir -p "$build_dir" "$work_dir/python"
python3 -m pip install --quiet --target "$work_dir/python" "$package"

output="$build_dir/driver-layer-$engine.zip"
rm -f "$output"
(cd "$work_dir" && zip --quiet --recurse-paths "$output" python --exclude '*/__pycache__/*')

echo "built $output"
