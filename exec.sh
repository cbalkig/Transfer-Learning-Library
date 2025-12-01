#!/usr/bin/env bash
set -Eeuo pipefail

die() { echo "Error: $*" >&2; exit 1; }

# --- args ---
[[ $# -ge 1 ]] || die "Please provide a .yaml config file (e.g., ./exec.sh m.yaml)"
CFG_FILE="$1"

[[ -f "$CFG_FILE" ]] || die "Config file not found: $CFG_FILE"
case "$CFG_FILE" in
  *.yaml|*.yml) : ;;
  *) die "Config must be a .yaml/.yml file: $CFG_FILE" ;;
esac

# Optional: grace period (seconds) before shutdown check (can override via env)
SHUTDOWN_GRACE_SECS="${SHUTDOWN_GRACE_SECS:-120}"

# --- enter repo root (directory containing this script) ---
cd "$(dirname "$0")"

# --- update repo (best-effort) ---
git pull --rebase --autostash || echo "git pull failed (continuing anyway)"

# --- logging setup ---
LOG_DIR="logs"
mkdir -p "$LOG_DIR"
TS="$(date '+%Y%m%d_%H%M%S')"
CFG_BASENAME="$(basename "$CFG_FILE")"
CFG_TAG="${CFG_BASENAME%.*}"
LOG_FILE="$LOG_DIR/main_${TS}_${CFG_TAG}.log"

# Symlink to the latest log for convenience
ln -sfn "$(basename "$LOG_FILE")" "$LOG_DIR/latest.log"

# --- start training under nohup ---
echo "Starting: ./.venv/bin/python create_file_list.py --cfg_file $CFG_FILE"
nohup ./.venv/bin/python create_file_list.py --cfg_file "$CFG_FILE" >> "$LOG_FILE" 2>&1 &
PY_PID=$!
echo "$PY_PID" > "$LOG_DIR/create_file_list.pid"

echo "main.py PID: $PY_PID"
echo "Log file   : $LOG_FILE"
echo "Latest log : $LOG_DIR/latest.log"
echo

# --- live log streaming if interactive ---
if [ -t 1 ]; then
  echo "Streaming logs. Press Ctrl-C to stop following (training continues in background)."
  echo "Tip: run '\''tail -f $LOG_FILE'\'' anytime."
  tail -n +1 -f "$LOG_FILE" &
  TAIL_PID=$!
  wait "$PY_PID" || true
  kill "$TAIL_PID" >/dev/null 2>&1 || true
  echo
  echo "main.py exited. See full logs in: $LOG_FILE"
else
  echo "Non-interactive session detected. Training continues under nohup."
  echo "Check progress later with: tail -f $LOG_FILE"
fi
