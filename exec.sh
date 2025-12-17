#!/usr/bin/env bash
set -Eeuo pipefail

die() { echo "Error: $*" >&2; exit 1; }

# --- args ---
[[ $# -ge 2 ]] || die "Usage: ./exec.sh <script_name> <config_file> (e.g., ./exec.sh dann neurodomain.yaml)"

SCRIPT_NAME="$1"  # e.g., "dann"
CFG_FILE="$2"     # e.g., "neurodomain.yaml"

# Construct the Python file path based on the script name provided
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

# --- 1. Parse YAML Metadata for Logging Structure ---
# We extract 'd', 't', and 'root_dir' early to build the log path
eval $(./.venv/bin/python -c "
import sys, yaml, re

try:
    with open('$CFG_FILE', 'r') as f:
        cfg = yaml.safe_load(f)

    # Safe retrieval of keys
    d_val = cfg.get('d', 'UnknownD')
    t_val = cfg.get('t', 'UnknownT')
    root_val = cfg.get('root_dir', '')

    print(f\"META_D='{d_val}'\")
    print(f\"META_T='{t_val}'\")
    print(f\"META_ROOT='{root_val}'\")

except Exception as e:
    # Fallback to defaults if parsing fails, so the script doesn't crash immediately
    print(\"META_D='UnknownD'\")
    print(\"META_T='UnknownT'\")
    print(\"META_ROOT=''\")
")

# --- 2. Extract Fold ID ---
# Regex to find 'k-fold-X' inside the root_dir string
if [[ "$META_ROOT" =~ k-fold-([0-9]+) ]]; then
    FOLD_ID="${BASH_REMATCH[1]}"
else
    FOLD_ID="0" # Default if not found
fi

# --- 3. Construct Log Directory ---
# Structure: logs / <d>_2_<t> / SCRIPT_NAME / <fold_id>
LOG_BASE="logs"
LOG_DIR="${LOG_BASE}/${META_D}_2_${META_T}/${SCRIPT_NAME}/${FOLD_ID}"

mkdir -p "$LOG_DIR"

TS="$(date '+%Y%m%d_%H%M%S')"
# Simplified filename since the directory structure now carries most of the info
LOG_FILE="$LOG_DIR/run_${TS}.log"

# Link 'latest.log' inside the specific folder for easy checking
ln -sfn "$(basename "$LOG_FILE")" "$LOG_DIR/latest.log"

echo "Log Directory: $LOG_DIR"
echo "Log File     : $LOG_FILE"

# --- Pre-processing ---
echo "Starting Pre-processing: ./.venv/bin/python create_file_list.py --cfg_file $CFG_FILE"
CUDA_VISIBLE_DEVICES=0 ./.venv/bin/python create_file_list.py --cfg_file "$CFG_FILE" >> "$LOG_FILE"

# --- Parse YAML to build arguments for main script ---
X_ARGS=$(./.venv/bin/python -c "
import sys, yaml

try:
    with open('$CFG_FILE', 'r') as f:
        cfg = yaml.safe_load(f)

    args = []

    # Keys to exclude from the generic loop because they are handled manually
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

#nohup ./.venv/bin/python "$PY_SCRIPT_PATH" \
#    $X_ARGS >> "$LOG_FILE" 2>&1 &

PY_PID=$!
# PID file saved in the specific log dir
echo "$PY_PID" > "$LOG_DIR/process.pid"

echo "PID          : $PY_PID"
echo

# --- live log streaming ---
if [ -t 1 ]; then
  echo "Streaming logs. Press Ctrl-C to stop following (training continues in background)."
  tail -n +1 -f "$LOG_FILE" &
  TAIL_PID=$!
  wait "$PY_PID" || true
  kill "$TAIL_PID" >/dev/null 2>&1 || true
  echo "Process exited. See full logs in: $LOG_FILE"
else
  echo "Non-interactive session. Check progress with: tail -f $LOG_FILE"
fi