#!/usr/bin/env bash
#
# Smoke-test each terp by feeding it a RemGlk init event plus one line
# input, then checking the first update for an expected substring. Pass
# means: terp started, accepted the JSON protocol, produced a structured
# update, and the update contained recognizable text from the test game.
#
# Usage:
#   tests/smoke.sh                     # run all tests
#   tests/smoke.sh -b <build-dir>      # override build dir
#   tests/smoke.sh -g <games-dir>      # override games dir
#   tests/smoke.sh bocfel scott        # only run named terps
#
set -u

# ---------------------------------------------------------------------------
# Defaults: assume layout vms-project/{flutterbug-terps,games}/.
# ---------------------------------------------------------------------------
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
BUILD_DIR="$REPO_DIR/build"
GAMES_DIR=$(cd "$REPO_DIR/.." && pwd)/games
ONLY=()

while getopts "b:g:h" opt; do
    case $opt in
        b) BUILD_DIR=$(cd "$OPTARG" && pwd) ;;
        g) GAMES_DIR=$(cd "$OPTARG" && pwd) ;;
        h) sed -n '/^# Usage:/,/^# *$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) exit 2 ;;
    esac
done
shift $((OPTIND - 1))
ONLY=("$@")

# ---------------------------------------------------------------------------
# Test cases. Format:
#   "label|binary|game (relative to GAMES_DIR)|input-window|expect-substring"
# Use binary== game="-" expect="-" for "smoke only" terps with no game file.
# ---------------------------------------------------------------------------
CASES=(
    "bocfel-z3|bocfel|zmachine/library.z3|2|Library Of Horror"
    "bocfel-z5|bocfel|zmachine/Advent.z5|2|At End Of Road"
    "glulxe   |glulxe|glulx/advent.ulx|1|At End Of Road"
    "git      |git|glulx/advent.ulx|1|At End Of Road"
    "tads-2   |tadsr|tads/ditch.gam|1|Ditch Day Drifter"
    "tads-3   |tadsr|tads/ditch3.t3|1|Return to Ditch Day"
    "scott-sa |scott|scott/adventureland.dat|1|ADVENTURELAND"
    "scott-pi |scott|scott/pirate.dat|1|pirate adventure"
    "scott-mb |scott|scott/golden_baton.dat|1|MYSTERIOUS ADVENTURES"
    "plus     |plus|-|-|-"
    "taylor   |taylor|-|-|-"
)

INIT='{"type":"init","gen":0,"metrics":{"width":80,"height":24},"support":["timer","graphics","graphicswin","hyperlinks","sounds","sounds2"]}'

# ---------------------------------------------------------------------------
# Per-case test runners. PASS / FAIL output is plain ASCII so the script is
# friendly to CI. Color escapes only when stdout is a TTY.
# ---------------------------------------------------------------------------
if [ -t 1 ]; then
    P="\033[32mPASS\033[0m"; F="\033[31mFAIL\033[0m"; S="\033[33mSKIP\033[0m"
else
    P="PASS"; F="FAIL"; S="SKIP"
fi

# Run the terp + check first non-disable update contains $expect.
# Stdin: init + one line event + 1 sec sleep so the terp can flush.
# Returns 0 if expect-substring found in the first update's text content.
run_with_game() {
    local terp_bin=$1 game=$2 win=$3 expect=$4
    {
        printf '%s\n' "$INIT"
        printf '{"type":"line","gen":1,"window":%s,"value":"look"}\n' "$win"
        sleep 1
    } | timeout 5 "$terp_bin" "$game" 2>/dev/null \
      | python3 -c "
import json, sys
expect = sys.argv[1]
for line in sys.stdin:
    s = line.strip()
    if not s.startswith('{'): continue
    try: d = json.loads(s)
    except: continue
    if d.get('disable'): continue
    blob_parts = []
    for c in d.get('content', []):
        for ln in c.get('lines', []):
            for x in ln.get('content', []):
                blob_parts.append(x.get('text',''))
        for t in c.get('text', []):
            for seg in t.get('content', []):
                blob_parts.append(seg.get('text',''))
    blob = ' '.join(blob_parts)
    sys.exit(0 if expect in blob else 1)
sys.exit(2)
" "$expect"
}

# Smoke-only: feed init alone, check the terp produced a clean disable
# update for a missing-game error rather than crashing.
run_smoke_only() {
    local terp_bin=$1
    {
        printf '%s\n' "$INIT"
        sleep 1
    } | timeout 5 "$terp_bin" /tmp/_no_such_game_$$ 2>/dev/null \
      | python3 -c "
import json, sys
for line in sys.stdin:
    s = line.strip()
    if not s.startswith('{'): continue
    try: d = json.loads(s)
    except: continue
    sys.exit(0)  # any structured update means no crash
sys.exit(1)
"
}

# ---------------------------------------------------------------------------
# Drive cases.
# ---------------------------------------------------------------------------
pass=0; fail=0; skip=0
echo "Build dir: $BUILD_DIR"
echo "Games dir: $GAMES_DIR"
echo

for case_line in "${CASES[@]}"; do
    IFS='|' read -r label terp game win expect <<< "$case_line"
    label=${label// /}; terp=${terp// /}

    if [ ${#ONLY[@]} -gt 0 ]; then
        match=0
        for want in "${ONLY[@]}"; do
            [ "$want" = "$terp" ] || [ "$want" = "$label" ] && match=1 && break
        done
        [ $match -eq 0 ] && continue
    fi

    bin="$BUILD_DIR/$terp"
    if [ ! -x "$bin" ]; then
        printf "  %-12s %b  (no binary at %s)\n" "$label" "$S" "$bin"
        skip=$((skip+1)); continue
    fi

    if [ "$game" = "-" ]; then
        if run_smoke_only "$bin"; then
            printf "  %-12s %b  smoke only (no freeware corpus)\n" "$label" "$P"
            pass=$((pass+1))
        else
            printf "  %-12s %b  smoke only — no JSON output\n" "$label" "$F"
            fail=$((fail+1))
        fi
        continue
    fi

    game_path="$GAMES_DIR/$game"
    if [ ! -f "$game_path" ]; then
        printf "  %-12s %b  (no game at %s)\n" "$label" "$S" "$game_path"
        skip=$((skip+1)); continue
    fi

    if run_with_game "$bin" "$game_path" "$win" "$expect"; then
        printf "  %-12s %b  found %q\n" "$label" "$P" "$expect"
        pass=$((pass+1))
    else
        printf "  %-12s %b  expected %q in first update\n" "$label" "$F" "$expect"
        fail=$((fail+1))
    fi
done

echo
echo "Total: $((pass+fail+skip))  pass=$pass  fail=$fail  skip=$skip"
[ $fail -eq 0 ]
