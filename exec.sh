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
export PYTHONPATH=$PYTHONPATH:.

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

echo "Starting: ./.venv/bin/python create_file_list.py --cfg_file $CFG_FILE"
./.venv/bin/python create_file_list.py --cfg_file "$CFG_FILE" >> "$LOG_FILE"

# --- Parse YAML to build arguments for dann.py ---
# This uses python to safely extract keys/values from the YAML 'dann' block
# and 'root_dir' to build the command line flags.
DANN_ARGS=$(./.venv/bin/python -c "
import sys, yaml
try:
    with open('$CFG_FILE', 'r') as f:
        cfg = yaml.safe_load(f)

    args = []

    # 1. Positional argument: Data Root (prefer 'root_dir' from yaml)
    if 'root_dir' in cfg:
        args.append(str(cfg['root_dir']))

    # 2. Append keys from the 'dann' section
    if 'dann' in cfg and isinstance(cfg['dann'], dict):
        for k, v in cfg['dann'].items():
            # Use single dash for single letter keys (-d), double for longer (--epochs)
            prefix = '-' if len(k) == 1 else '--'
            args.append(f'{prefix}{k} {v}')

    print(' '.join(args))
except Exception as e:
    # Print error to stderr so it doesn't get captured into the variable
    print(f'Error parsing yaml: {e}', file=sys.stderr)
    sys.exit(1)
")

# --- start training under nohup ---
echo "Starting: ./.venv/bin/python examples/domain_adaptation/image_classification/dann.py $DANN_ARGS"

# Removed \"$CFG_FILE\" from the end of the command below as requested
nohup ./.venv/bin/python ./examples/domain_adaptation/image_classification/dann.py --scratch \
    $DANN_ARGS >> "$LOG_FILE" 2>&1 &

PY_PID=$!
echo "$PY_PID" > "$LOG_DIR/dann.pid"

echo "dann.py PID: $PY_PID"
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
  echo "dann.py exited. See full logs in: $LOG_FILE"
else
  echo "Non-interactive session detected. Training continues under nohup."
  echo "Check progress later with: tail -f $LOG_FILE"
fi