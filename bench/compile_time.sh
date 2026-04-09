#!/usr/bin/env bash
#
# Compare compile-time overhead of Localize vs ex_cldr.
#
# Runs each measurement multiple times from a clean state and
# reports the best wall-clock time. Measurements:
#
#   1. Clean deps compile (ex_cldr family) — the ex_cldr hex
#      packages that the :bench environment pulls in.
#
#   2. Full Localize project compile including `lib/` —
#      Localize's own source (ex_cldr-family deps already cached).
#
#   3. Full `Bench.Cldr` backend compile — the per-project ex_cldr
#      compile cost an end user pays every time they add or remove
#      a locale or provider from their backend module.
#
#   4. Incremental Localize recompile after touching a leaf module —
#      the Localize equivalent of (3), for comparison.
#
# Run with:
#
#     MIX_ENV=bench bench/compile_time.sh
#
# or pass an iteration count as the first argument:
#
#     MIX_ENV=bench bench/compile_time.sh 5

set -euo pipefail

ITERATIONS="${1:-3}"
export MIX_ENV=bench

cd "$(dirname "$0")/.."

# Portable wall-clock measurement. `time` output format varies
# across shells; we use Elixir's built-in :os.system_time for
# sub-millisecond precision.
measure() {
  local label="$1"
  shift
  local start end elapsed
  start=$(date +%s%N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1e9))')
  "$@" >/dev/null 2>&1
  end=$(date +%s%N 2>/dev/null || python3 -c 'import time; print(int(time.time()*1e9))')
  elapsed=$(( (end - start) / 1000000 ))
  printf "  %-60s %8d ms\n" "$label" "$elapsed"
  echo "$elapsed"
}

best_of() {
  local label="$1"
  shift
  local best=99999999
  local run
  for i in $(seq 1 "$ITERATIONS"); do
    run=$("$@")
    if [ "$run" -lt "$best" ]; then
      best="$run"
    fi
  done
  printf "  %-60s best: %8d ms (of %d runs)\n" "$label" "$best" "$ITERATIONS"
}

echo ""
echo "============================================================"
echo " Compile-time benchmark: Localize vs ex_cldr"
echo " MIX_ENV=bench, iterations=${ITERATIONS}"
echo "============================================================"
echo ""

# Ensure deps are fetched once up-front.
mix deps.get >/dev/null

# ── 1. Clean deps compile ────────────────────────────────────────
#
# Force-recompile all hex deps (ex_cldr family + benchee tree).
# Run this multiple times; the best-of result represents the
# minimum wall-clock cost of first-build when ex_cldr is added to
# a project.
echo "[1] Clean compile of ex_cldr family deps"

deps_iter() {
  mix deps.clean --all >/dev/null 2>&1
  mix deps.get >/dev/null 2>&1
  local start end
  start=$(date +%s 2>/dev/null)
  mix deps.compile >/dev/null 2>&1
  end=$(date +%s 2>/dev/null)
  echo $(( (end - start) * 1000 ))
}

best=99999999
for i in $(seq 1 "$ITERATIONS"); do
  run=$(deps_iter)
  printf "    run %d: %8d ms\n" "$i" "$run"
  if [ "$run" -lt "$best" ]; then
    best="$run"
  fi
done
printf "  ex_cldr deps total (best):                            %8d ms\n" "$best"
echo ""

# ── 2. Full Localize project compile ─────────────────────────────
#
# Clean only the _build/bench/lib/localize directory so deps stay
# cached. This measures the time to compile Localize's own lib/
# tree in the :bench environment.
echo "[2] Full Localize project compile (lib/ only, deps cached)"

localize_iter() {
  rm -rf _build/bench/lib/localize
  local start end
  start=$(date +%s 2>/dev/null)
  mix compile >/dev/null 2>&1
  end=$(date +%s 2>/dev/null)
  echo $(( (end - start) * 1000 ))
}

best=99999999
for i in $(seq 1 "$ITERATIONS"); do
  run=$(localize_iter)
  printf "    run %d: %8d ms\n" "$i" "$run"
  if [ "$run" -lt "$best" ]; then
    best="$run"
  fi
done
printf "  Localize lib/ compile (best):                         %8d ms\n" "$best"
echo ""

# ── 3. Clean Bench.Cldr backend compile ──────────────────────────
#
# The per-project ex_cldr cost: touching the backend file and
# letting mix compile regenerate it. This is the compile pain an
# end user feels every time they change providers or locales in
# their backend module. The ex_cldr hex packages are cached, so
# this only measures the backend module's own compilation.
echo "[3] Bench.Cldr backend recompile (touch backend file)"

backend_iter() {
  # Ensure everything is compiled first.
  mix compile >/dev/null 2>&1
  # Delete the backend beam so the next compile rebuilds it.
  find _build/bench/lib/localize/ebin -name 'Elixir.Bench.Cldr*' -delete 2>/dev/null || true
  touch ex_cldr/bench_cldr.ex
  local start end
  start=$(date +%s 2>/dev/null)
  mix compile >/dev/null 2>&1
  end=$(date +%s 2>/dev/null)
  echo $(( (end - start) * 1000 ))
}

best=99999999
for i in $(seq 1 "$ITERATIONS"); do
  run=$(backend_iter)
  printf "    run %d: %8d ms\n" "$i" "$run"
  if [ "$run" -lt "$best" ]; then
    best="$run"
  fi
done
printf "  Bench.Cldr backend recompile (best):                  %8d ms\n" "$best"
echo ""

# ── 4. Touch-one-leaf-module Localize recompile ──────────────────
#
# The Localize equivalent of the backend recompile. Touching a
# single Localize module triggers a partial recompile through
# Mix's dependency graph. This is the best per-project cost
# comparison against (3).
echo "[4] Localize incremental recompile (touch one module)"

TOUCH_TARGET="lib/localize/number.ex"
if [ ! -f "$TOUCH_TARGET" ]; then
  TOUCH_TARGET=$(find lib/localize -name '*.ex' -type f | head -1)
fi

localize_touch_iter() {
  mix compile >/dev/null 2>&1
  touch "$TOUCH_TARGET"
  local start end
  start=$(date +%s 2>/dev/null)
  mix compile >/dev/null 2>&1
  end=$(date +%s 2>/dev/null)
  echo $(( (end - start) * 1000 ))
}

best=99999999
for i in $(seq 1 "$ITERATIONS"); do
  run=$(localize_touch_iter)
  printf "    run %d: %8d ms\n" "$i" "$run"
  if [ "$run" -lt "$best" ]; then
    best="$run"
  fi
done
printf "  Localize touch-and-recompile (best):                  %8d ms\n" "$best"
echo ""

echo "============================================================"
echo " Interpretation"
echo "============================================================"
echo ""
echo "[1] First-time ex_cldr dep install cost (cached after the"
echo "    first build on a given machine / CI cache layer)."
echo ""
echo "[2] Localize's own lib/ compile cost. Cached in the same way."
echo ""
echo "[3] ex_cldr per-project compile cost — paid every time you"
echo "    edit bench_cldr.ex to add/remove a locale or provider."
echo "    This is the cost end users feel in their dev loop."
echo ""
echo "[4] Localize has no backend module, so the closest equivalent"
echo "    is incremental recompile of one source file. In a real"
echo "    end-user project of Localize, the per-project backend"
echo "    compile cost is zero — there is no backend."
echo ""
