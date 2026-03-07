#!/usr/bin/env bash
# jank-lifecycle.sh — manage the jank nREPL process.
#
# Usage:
#   jank-lifecycle.sh start   — start jank if not running, print port
#   jank-lifecycle.sh stop    — stop jank, clean up files
#   jank-lifecycle.sh status  — print port if running, exit 1 if not

set -euo pipefail

# Resolve project root: walk up from this script's directory to find _quarto.yml.
# Falls back to the current working directory if not found.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT=""
_dir="$SCRIPT_DIR"
while [ "$_dir" != "/" ]; do
    if [ -f "$_dir/_quarto.yml" ]; then
        PROJECT_ROOT="$_dir"
        break
    fi
    _dir="$(dirname "$_dir")"
done
if [ -z "$PROJECT_ROOT" ]; then
    PROJECT_ROOT="$(pwd)"
fi

PID_FILE="$PROJECT_ROOT/.jank-pid"
PORT_FILE="$PROJECT_ROOT/.jank-nrepl-port"
LOG_FILE="$PROJECT_ROOT/.jank-repl.log"

# Validate that a string is a positive integer (PID or port).
is_number() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

# Read and validate a PID from the PID file.
# Returns the PID via stdout, or returns 1 if invalid/missing.
read_pid() {
    if [ ! -f "$PID_FILE" ]; then
        return 1
    fi
    local pid
    pid=$(cat "$PID_FILE")
    if ! is_number "$pid"; then
        echo "WARNING: Corrupt PID file, removing." >&2
        rm -f "$PID_FILE" "$PORT_FILE"
        return 1
    fi
    echo "$pid"
}

# Check if a given PID belongs to a jank-related process.
# Prevents accidentally killing an unrelated process that reused the PID.
is_jank_process() {
    local pid="$1"
    local comm
    comm=$(ps -o comm= -p "$pid" 2>/dev/null | tr -d ' ') || return 1
    # The process may be "jank" itself or "bash" (the wrapper that runs jank)
    [[ "$comm" == "jank" || "$comm" == "bash" ]]
}

# Check if the jank process recorded in PID_FILE is still alive.
is_running() {
    local pid
    pid=$(read_pid) || return 1
    if kill -0 "$pid" 2>/dev/null && is_jank_process "$pid"; then
        return 0
    fi
    # Stale PID file — process is dead or reused by another program
    rm -f "$PID_FILE" "$PORT_FILE"
    return 1
}

# Discover jank's nREPL port from a running process.
# Uses lsof (cross-platform) with ss as fallback (Linux).
discover_port() {
    local pid="${1:-}"

    # Try lsof first (works on Linux and macOS)
    if command -v lsof >/dev/null 2>&1; then
        local port=""
        if [ -n "$pid" ]; then
            port=$(lsof -a -iTCP -sTCP:LISTEN -nP -p "$pid" 2>/dev/null \
                   | awk -F: '/LISTEN/ {print $NF}' | awk '{print $1}' | head -1)
        else
            port=$(lsof -iTCP -sTCP:LISTEN -nP 2>/dev/null \
                   | awk '/jank.*LISTEN/ {split($NF, a, ":"); print a[2]}' | head -1)
        fi
        if [ -n "$port" ] && is_number "$port"; then
            echo "$port"
            return 0
        fi
    fi

    # Fallback: ss (Linux only)
    if command -v ss >/dev/null 2>&1; then
        local port=""
        if [ -n "$pid" ]; then
            port=$(ss -tlnp 2>/dev/null | grep "pid=$pid" \
                   | awk '{print $4}' | awk -F: '{print $NF}' | head -1)
        else
            port=$(ss -tlnp 2>/dev/null | grep '"jank"' \
                   | awk '{print $4}' | awk -F: '{print $NF}' | head -1)
        fi
        if [ -n "$port" ] && is_number "$port"; then
            echo "$port"
            return 0
        fi
    fi

    return 1
}

cmd_start() {
    # Already running?
    if is_running; then
        if [ -f "$PORT_FILE" ]; then
            cat "$PORT_FILE"
            exit 0
        fi
        # PID alive but no port file — rediscover
        local pid
        pid=$(read_pid)
        local port
        port=$(discover_port "$pid") || true
        if [ -n "$port" ]; then
            echo "$port" > "$PORT_FILE"
            echo "$port"
            exit 0
        fi
        echo "ERROR: jank running (PID $pid) but cannot discover port" >&2
        exit 1
    fi

    echo "[jank-lifecycle] Starting jank repl..." >&2

    # Start jank repl with stdin held open.
    # tail -f /dev/null blocks forever (cross-platform, unlike sleep infinity).
    bash -c 'jank repl < <(tail -f /dev/null)' > "$LOG_FILE" 2>&1 &
    local wrapper_pid=$!

    # Wait briefly for jank to spawn as a child of the bash wrapper
    sleep 0.5

    # Find the actual jank process (child of the wrapper)
    local jank_pid
    jank_pid=$(pgrep -P "$wrapper_pid" -x jank 2>/dev/null || echo "")
    if [ -z "$jank_pid" ]; then
        # Fallback: the wrapper itself might be jank
        jank_pid=$wrapper_pid
    fi

    echo "$jank_pid" > "$PID_FILE"

    # Start background monitor: cleans up files when jank dies
    (
        while kill -0 "$jank_pid" 2>/dev/null; do
            sleep 10
        done
        rm -f "$PID_FILE" "$PORT_FILE"
    ) &
    disown

    # Poll for port discovery (jank takes ~15s to start)
    local port=""
    for i in $(seq 1 45); do
        sleep 1
        port=$(discover_port "$jank_pid") || true
        if [ -n "$port" ]; then
            echo "$port" > "$PORT_FILE"
            echo "[jank-lifecycle] Jank started on port $port (PID $jank_pid)" >&2
            echo "$port"
            exit 0
        fi
        # Check jank hasn't died during startup
        if ! kill -0 "$jank_pid" 2>/dev/null; then
            echo "ERROR: jank process died during startup. Check $LOG_FILE" >&2
            rm -f "$PID_FILE"
            exit 1
        fi
    done

    echo "ERROR: Timed out waiting for jank nREPL to start (45s). Check $LOG_FILE" >&2
    kill "$jank_pid" 2>/dev/null || true
    rm -f "$PID_FILE"
    exit 1
}

# Kill a process and its children, with safety checks.
safe_kill_jank() {
    local pid="$1"

    # Verify the PID still belongs to a jank-related process
    if ! is_jank_process "$pid"; then
        echo "WARNING: PID $pid is no longer a jank process, skipping kill." >&2
        return 0
    fi

    # Kill the specific process and its direct children (tail, jank subprocess)
    # rather than the whole process group, to avoid collateral damage.
    kill "$pid" 2>/dev/null || true
    pkill -P "$pid" 2>/dev/null || true
}

cmd_stop() {
    if [ ! -f "$PID_FILE" ]; then
        echo "[jank-lifecycle] No PID file found — cannot determine which jank process belongs to this project." >&2
        echo "[jank-lifecycle] If a jank process is running, stop it manually with: kill <PID>" >&2
        rm -f "$PORT_FILE"
        return 0
    fi

    local pid
    pid=$(read_pid) || {
        rm -f "$PID_FILE" "$PORT_FILE"
        return 0
    }

    echo "[jank-lifecycle] Stopping jank (PID $pid)..." >&2
    safe_kill_jank "$pid"

    rm -f "$PID_FILE" "$PORT_FILE"
    echo "[jank-lifecycle] Jank stopped." >&2
}

cmd_status() {
    if is_running; then
        local pid
        pid=$(read_pid)
        if [ -f "$PORT_FILE" ]; then
            local port
            port=$(cat "$PORT_FILE")
            echo "running on port $port (PID $pid)"
        else
            echo "running (PID $pid, port unknown)"
        fi
        exit 0
    fi

    # Check for untracked jank processes (current user only)
    local pid
    pid=$(pgrep -u "$(id -u)" -x jank 2>/dev/null || echo "")
    if [ -n "$pid" ]; then
        local port
        port=$(discover_port "$pid") || true
        echo "running on port ${port:-unknown} (PID $pid, untracked)"
        exit 0
    fi

    echo "not running"
    exit 1
}

case "${1:-}" in
    start)  cmd_start ;;
    stop)   cmd_stop ;;
    status) cmd_status ;;
    *)
        echo "Usage: $0 {start|stop|status}" >&2
        exit 1
        ;;
esac
