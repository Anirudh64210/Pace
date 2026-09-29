import Foundation

/// The status line script, embedded so the app can install it. Kept byte-for-byte
/// identical to `scripts/pace-statusline.sh` (a unit test checks this).
enum StatusLineScript {
    static let contents = #"""
#!/bin/bash
# Pace status line for Claude Code.
#
# Claude Code pipes a JSON blob to this script on stdin. The script saves the
# rate limit numbers to ~/Library/Application Support/Pace/status.json (which
# the Pace menu bar app reads) and prints a one-line status for the terminal.
#
# No credentials are involved. Nothing leaves your Mac. Only numbers are saved.
#
# If ~/.claude/pace-statusline-chain exists, it holds the status line command
# you had before Pace was installed. This script runs that command and prints
# its output instead of Pace's line, so your terminal looks the same as before.
#
# Uninstall: Pace > Settings > Remove, or delete the "statusLine" entry from
# ~/.claude/settings.json and this file.
set -u

ORIGINAL_UMASK="$(umask)"
umask 077
DIR="$HOME/Library/Application Support/Pace"
CHAIN="$HOME/.claude/pace-statusline-chain"
INPUT="$(cat)"
mkdir -p "$DIR"

# Only run the saved command if it is yours and nobody else can change it.
QUIET=0
if [ -s "$CHAIN" ] && [ -O "$CHAIN" ] && [ -z "$(find "$CHAIN" -perm +022 2>/dev/null)" ]; then
  QUIET=1
fi

# /usr/bin/python3 ships with the Xcode Command Line Tools. Without them it is a
# stub that opens an installer dialog, so check quietly first.
if /usr/bin/xcode-select -p >/dev/null 2>&1 && [ -x /usr/bin/python3 ]; then
printf '%s' "$INPUT" | PACE_QUIET="$QUIET" /usr/bin/python3 -c "
import json, os, sys, time, datetime, math, tempfile, fcntl
out = sys.argv[1]
now = time.time()
try:
    d = json.loads(sys.stdin.read() or '{}')
except Exception:
    d = {}
rl = d.get('rate_limits') if isinstance(d, dict) else {}
if not isinstance(rl, dict):
    rl = {}

def num(x):
    try:
        v = float(x)
        return v if math.isfinite(v) else None
    except Exception:
        return None

def clean(w):
    # Keep a window only with a sane percentage, and a reset time that is either
    # missing or within the next eight days (a weekly window is seven).
    if not isinstance(w, dict):
        return None
    p = num(w.get('used_percentage'))
    if p is None:
        return None
    r = num(w.get('resets_at'))
    if r is not None and not (now - 86400 < r < now + 8 * 86400):
        r = None
    return {'used_percentage': max(0.0, min(1000.0, p)), 'resets_at': r}

# Several Claude Code sessions run this script at once, and an idle session
# reports stale numbers. Under a lock, merge per window: a later reset time
# wins, the same window keeps the higher usage, a missing window keeps what was
# saved before.
lock = open(os.path.join(os.path.dirname(out), 'status.lock'), 'a')
fcntl.flock(lock, fcntl.LOCK_EX)
try:
    old = {}
    try:
        with open(out) as f:
            old = json.load(f).get('rate_limits') or {}
    except Exception:
        old = {}
    if not isinstance(old, dict):
        old = {}
    merged = {}
    for k in ('five_hour', 'seven_day', 'spend_limit'):
        n, o = clean(rl.get(k)), clean(old.get(k))
        nr, orr = (n or {}).get('resets_at') or 0, (o or {}).get('resets_at') or 0
        if n is None and o is None:
            continue
        if n is None:
            merged[k] = o
        elif o is None or nr > orr + 1:
            merged[k] = n
        elif nr >= orr - 1:
            merged[k] = dict(n, used_percentage=max(n['used_percentage'], o['used_percentage']))
        else:
            merged[k] = o
    rl = merged
    payload = {'rate_limits': rl, 'pace_saved_at': now}
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(out), prefix='.status.', suffix='.tmp')
    try:
        with os.fdopen(fd, 'w') as f:
            json.dump(payload, f, allow_nan=False)
        os.replace(tmp, out)
    except Exception:
        try:
            os.unlink(tmp)
        except Exception:
            pass
finally:
    fcntl.flock(lock, fcntl.LOCK_UN)
    lock.close()

if os.environ.get('PACE_QUIET') == '1':
    sys.exit(0)
five = rl.get('five_hour') or {}
week = rl.get('seven_day') or {}
if not five and not week:
    print('● Pace: waiting for first response')
    sys.exit(0)
def left(w):
    p = w.get('used_percentage')
    return None if p is None else max(0, min(100, 100 - p))
def until(w):
    r = w.get('resets_at')
    if not r:
        return ''
    s = max(0, int(r - now))
    h, m = s // 3600, (s % 3600) // 60
    return ('%dh %02dm' % (h, m)) if h else ('%dm' % m)
def weekday(w):
    r = w.get('resets_at')
    return datetime.datetime.fromtimestamp(r).strftime('%a') if r else ''
sl, wl = left(five), left(week)
if wl is not None and wl <= 0:
    status = 'week limit'
elif sl is not None and sl <= 0:
    status = 'session limit'
elif sl is not None and sl >= 100:
    status = 'fresh session'
else:
    status = 'on track'
parts = ['● ' + status]
if sl is not None:
    parts.append('%d%% session · %s' % (round(sl), until(five) or 'full'))
if wl is not None:
    parts.append('%d%% week · %s' % (round(wl), weekday(week)))
print('  '.join(parts))
" "$DIR/status.json"
elif [ "$QUIET" = 0 ]; then
  echo "● Pace needs the Xcode Command Line Tools: xcode-select --install"
fi

if [ "$QUIET" = 1 ]; then
  umask "$ORIGINAL_UMASK"
  printf '%s' "$INPUT" | bash -c "$(cat "$CHAIN")"
fi
"""#
}
