#!/usr/bin/env bash
# Usage: ci-summary.sh <xcodebuild log> <label>
# Logs aren't downloadable from every environment, so say plainly what happened as workflow annotations:
# counts, failing cases, the last lines, and (for UI tests) the elements the app really showed at a failed lookup.
LOG="$1"; LABEL="$2"
[ -f "$LOG" ] || { echo "::notice title=$LABEL::no log produced"; exit 0; }
CLEAN="${LOG%.log}-clean.log"
grep -v 'CoreData:' "$LOG" > "$CLEAN" || true
ROOT='#/Users/runner/work/Palabra/Palabra/##'
{
  echo "$LABEL: passed cases: $(grep -cE "^Test Case .* passed" "$CLEAN")  failed cases: $(grep -cE "^Test Case .* failed" "$CLEAN")"
  grep -E "^Test Suite '[A-Za-z]+Tests' failed" "$CLEAN" | sed -E "s/ at [0-9-]+ [0-9:.]+\.?//" | awk '!seen[$0]++'
  grep -E "Test Case .* failed|TEST FAILED|TEST EXECUTE FAILED|: error:|XCTAssert|Failing tests|crashed|timed out" "$CLEAN" \
    | sed "s$ROOT" | cut -c1-300 | awk '!seen[$0]++' | head -40
  echo "--- slowest test cases:"
  grep -E "^Test Case .* passed \(" "$CLEAN" | sed -E "s/^Test Case '-\[([^]]*)\]' passed \(([0-9.]+) seconds\)\./\2 \1/" | sort -rn | head -12
  grep -E "^\s*Executed [0-9]+ tests" "$CLEAN" | tail -1
  echo "--- last 25 log lines:"
  tail -n 25 "$CLEAN" | cut -c1-240
} > "${LOG%.log}-summary.txt"
cat "${LOG%.log}-summary.txt" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
python3 - "$LOG" "$LABEL" <<'PY'
import sys
log, label = sys.argv[1], sys.argv[2]
enc = lambda s: s.replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')
print('::notice title=%s summary::%s' % (label, enc(open(log.rsplit('.', 1)[0] + '-summary.txt', errors='replace').read())))
lines = open(log.rsplit('.', 1)[0] + '-clean.log', errors='replace').read().split('\n')
shown = 0
for i, line in enumerate(lines):
    if ('No matches found' in line or 'Failed to' in line) and ': error:' in line and shown < 4:
        shown += 1
        print('::notice title=%s failure detail %d::%s' % (label, shown, enc('\n'.join(l[:200] for l in lines[i:i + 45]))))
PY
