#!/usr/bin/env bash
set -Eeuo pipefail

die() { echo "Error: $*" >&2; exit 1; }

# --- args ---
[[ $# -ge 2 ]] || die "Usage: ./exec.sh <script_name> <config_file> (e.g., ./exec.sh dann neurodomain.yaml)"

SCRIPT_NAME="$1"  # e.g., "dann"
CFG_FILE="$2"     # e.g., "neurodomain.yaml"

# Path to the python script
PY_SCRIPT_PATH="examples/domain_adaptation/image_classification/${SCRIPT_NAME}.py"

[[ -f "$CFG_FILE" ]] || die "Config file not found: $CFG_FILE"
[[ -f "$PY_SCRIPT_PATH" ]] || die "Python script not found: $PY_SCRIPT_PATH"

case "$CFG_FILE" in
  *.yaml|*.yml) : ;;
  *) die "Config must be a .yaml/.yml file: $CFG_FILE" ;;
esac

# --- enter repo root ---
cd "$(dirname "$0")"
export PYTHONPATH=.

# --- update repo ---
git pull --rebase --autostash || echo "git pull failed (continuing anyway)"

# --- Bash Logging Setup (Standard) ---
LOG_DIR="logs"
mkdir -p "$LOG_DIR"
TS="$(date '+%Y%m%d_%H%M%S')"
CFG_BASENAME="$(basename "$CFG_FILE")"
CFG_TAG="${CFG_BASENAME%.*}"

# Bash log captures stdout/stderr
LOG_FILE="$LOG_DIR/main_${SCRIPT_NAME}_${TS}_${CFG_TAG}.log"
ln -sfn "$(basename "$LOG_FILE")" "$LOG_DIR/latest.log"

echo "Starting Pre-processing: ./.venv/bin/python create_file_list.py --cfg_file $CFG_FILE"
CUDA_VISIBLE_DEVICES=0 ./.venv/bin/python create_file_list.py --cfg_file "$CFG_FILE" >> "$LOG_FILE"

# --- Parse YAML & Build Dynamic Arguments ---
# We pass SCRIPT_NAME into the python block to build the specific log path
X_ARGS=$(./.venv/bin/python -c "
import sys, yaml, re, os

try:
    with open('$CFG_FILE', 'r') as f:
        cfg = yaml.safe_load(f)

    args = []

    # 1. Extract Metadata for Dynamic Log Path
    d_val = cfg.get('d', 'UnknownD')
    t_val = cfg.get('t', 'UnknownT')
    root_val = cfg.get('root_dir', '')
    log_val = cfg.get('log_dir', '')
    fold_id = cfg.get('k-fold-id', 0)

    # Construct the dynamic log path: logs / <d>_2_<t> / SCRIPT_NAME / <fold_id>
    # Note: We use the SCRIPT_NAME passed from bash
    script_name = '$SCRIPT_NAME'
    dynamic_log_path = os.path.join(log_val, f'{d_val}_2_{t_val}', script_name, fold_id)

    # 2. Add the dynamic log argument
    args.append(f'--log {dynamic_log_path}')

    # 3. Handle Positional & Boolean Args
    # 'root_dir': Positional arg
    # 'scratch': Boolean flag
    # 'log': We ignore the YAML log path to use our dynamic one
    ignore_keys = {'root_dir', 'scratch', 'log_dir', 'k-fold-id'}

    if 'root_dir' in cfg:
        args.append(str(cfg['root_dir']))

    if cfg.get('scratch') is True:
        args.append('--scratch')

    # 4. Handle all other keys
    for k, v in cfg.items():
        if k not in ignore_keys:
            prefix = '-' if len(k) == 1 else '--'
            args.append(f'{prefix}{k} {v}')

    print(' '.join(args))
except Exception as e:
    print(f'Error parsing yaml: {e}', file=sys.stderr)
    sys.exit(1)
")

# --- Start Training ---
echo "Starting Training: ./.venv/bin/python $PY_SCRIPT_PATH $X_ARGS"
echo "Check main log at: $LOG_FILE"

#nohup ./.venv/bin/python "$PY_SCRIPT_PATH" \
#    $X_ARGS >> "$LOG_FILE" 2>&1 &

PY_PID=$!
echo "$PY_PID" > "$LOG_DIR/${SCRIPT_NAME}.pid"

echo "${SCRIPT_NAME}.py PID: $PY_PID"
echo

# --- live log streaming ---
if [ -t 1 ]; then
  echo "Streaming logs. Press Ctrl-C to stop following (training continues in background)."
  tail -n +1 -f "$LOG_FILE" &
  TAIL_PID=$!
  wait "$PY_PID" || true
  kill "$TAIL_PID" >/dev/null 2>&1 || true
  echo "${SCRIPT_NAME}.py exited."
else
  echo "Non-interactive session. Check progress with: tail -f $LOG_FILE"
fi