#!/usr/bin/env bash
set -Eeuo pipefail

die() { echo "Error: $*" >&2; exit 1; }

# --- args ---
[[ $# -ge 2 ]] || die "Usage: ./exec.sh <script_name> <config_file> (e.g., ./exec.sh dann neurodomain.yaml)"

SCRIPT_NAME="$1"  # e.g., "dann"
CFG_FILE="$2"     # e.g., "neurodomain.yaml"

# Construct the Python file path based on the script name provided
# Assumes the script lives in examples/domain_adaptation/image_classification/
PY_SCRIPT_PATH="examples/domain_adaptation/image_classification/${SCRIPT_NAME}.py"

[[ -f "$CFG_FILE" ]] || die "Config file not found: $CFG_FILE"
[[ -f "$PY_SCRIPT_PATH" ]] || die "Python script not found: $PY_SCRIPT_PATH"

case "$CFG_FILE" in
  *.yaml|*.yml) : ;;
  *) die "Config must be a .yaml/.yml file: $CFG_FILE" ;;
esac

# Optional: grace period (seconds) before shutdown check
SHUTDOWN_GRACE_SECS="${SHUTDOWN_GRACE_SECS:-120}"

# --- enter repo root ---
cd "$(dirname "$0")"
export PYTHONPATH=.

# --- update repo ---
git pull --rebase --autostash || echo "git pull failed (continuing anyway)"

# --- logging setup ---
LOG_DIR="logs"
mkdir -p "$LOG_DIR"
TS="$(date '+%Y%m%d_%H%M%S')"
CFG_BASENAME="$(basename "$CFG_FILE")"
CFG_TAG="${CFG_BASENAME%.*}"

# Log file now includes the script name (e.g., main_dann_2023..._neurodomain.log)
LOG_FILE="$LOG_DIR/main_${SCRIPT_NAME}_${TS}_${CFG_TAG}.log"
ln -sfn "$(basename "$LOG_FILE")" "$LOG_DIR/latest.log"

echo "Starting Pre-processing: ./.venv/bin/python create_file_list.py --cfg_file $CFG_FILE"
CUDA_VISIBLE_DEVICES=0 ./.venv/bin/python create_file_list.py --cfg_file "$CFG_FILE" >> "$LOG_FILE"

# --- Parse YAML to build arguments for given py ---
X_ARGS=$(./.venv/bin/python -c "
import sys, yaml

try:
    with open('$CFG_FILE', 'r') as f:
        cfg = yaml.safe_load(f)

    args = []

    # Keys to exclude from the generic loop because they are handled manually
    # 'root_dir': Positional arg
    # 'scratch': Boolean flag
    ignore_keys = {'root_dir', 'scratch'}

    # 1. Positional argument: Data Root
    if 'root_dir' in cfg:
        args.append(str(cfg['root_dir']))

    # 2. Handle 'scratch' boolean flag specifically
    if cfg.get('scratch') is True:
        args.append('--scratch')

    # 3. Handle all other top-level keys
    for k, v in cfg.items():
        if k not in ignore_keys:
            prefix = '-' if len(k) == 1 else '--'
            args.append(f'{prefix}{k} {v}')

    print(' '.join(args))
except Exception as e:
    print(f'Error parsing yaml: {e}', file=sys.stderr)
    sys.exit(1)
")

# --- start training under nohup ---
echo "Starting Training: ./.venv/bin/python $PY_SCRIPT_PATH $X_ARGS"

# Execute the dynamic script path
nohup ./.venv/bin/python "$PY_SCRIPT_PATH" \
    $X_ARGS >> "$LOG_FILE" 2>&1 &

PY_PID=$!
# PID file is named after the script (e.g., logs/dann.pid)
echo "$PY_PID" > "$LOG_DIR/${SCRIPT_NAME}.pid"

echo "${SCRIPT_NAME}.py PID: $PY_PID"
echo "Log file   : $LOG_FILE"
echo "Latest log : $LOG_DIR/latest.log"
echo

# --- live log streaming ---
if [ -t 1 ]; then
  echo "Streaming logs. Press Ctrl-C to stop following (training continues in background)."
  tail -n +1 -f "$LOG_FILE" &
  TAIL_PID=$!
  wait "$PY_PID" || true
  kill "$TAIL_PID" >/dev/null 2>&1 || true
  echo "${SCRIPT_NAME}.py exited. See full logs in: $LOG_FILE"
else
  echo "Non-interactive session. Check progress with: tail -f $LOG_FILE"
fi