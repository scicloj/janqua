#!/usr/bin/env bash
# jank-lifecycle.sh — manage the jank nREPL process.
#
# Usage:
#   jank-lifecycle.sh start   — start jank if not running, print port
#   jank-lifecycle.sh stop    — stop jank, clean up files
#   jank-lifecycle.sh status  — print port if running, exit 1 if not

set -euo pipefail

# Resolve project root: walk up from this script's directory to find _quarto.yml
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
while [ "$PROJECT_ROOT" != "/" ]; do
    if [ -f "$PROJECT_ROOT/_quarto.yml" ]; then
        break
    fi
    PROJECT_ROOT="$(dirname "$PROJECT_ROOT")"
done

PID_FILE="$PROJECT_ROOT/.jank-pid"
PORT_FILE="$PROJECT_ROOT/.jank-nrepl-port"
LOG_FILE="/tmp/jank-repl.log"

# Check if the jank process recorded in PID_FILE is still alive.
is_running() {
    if [ -f "$PID_FILE" ]; then
        local pid
        pid=$(cat "$PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
        # Stale PID file — clean up
        rm -f "$PID_FILE" "$PORT_FILE"
    fi
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
        if [ -n "$port" ]; then
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
        if [ -n "$port" ]; then
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
        pid=$(cat "$PID_FILE")
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

cmd_stop() {
    if [ ! -f "$PID_FILE" ]; then
        # Try to find jank by process name
        local pid
        pid=$(pgrep -x jank 2>/dev/null || echo "")
        if [ -n "$pid" ]; then
            echo "[jank-lifecycle] Stopping jank (PID $pid)..." >&2
            kill "$pid" 2>/dev/null || true
        else
            echo "[jank-lifecycle] No jank process found." >&2
        fi
        rm -f "$PORT_FILE"
        return 0
    fi

    local pid
    pid=$(cat "$PID_FILE")
    echo "[jank-lifecycle] Stopping jank (PID $pid)..." >&2

    # Kill jank and its parent bash wrapper (same process group)
    local pgid
    pgid=$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')
    if [ -n "$pgid" ]; then
        kill -- -"$pgid" 2>/dev/null || true
    fi
    # Also signal the specific PID in case PGID kill missed it
    kill "$pid" 2>/dev/null || true

    rm -f "$PID_FILE" "$PORT_FILE"
    echo "[jank-lifecycle] Jank stopped." >&2
}

cmd_status() {
    if is_running; then
        local pid
        pid=$(cat "$PID_FILE")
        if [ -f "$PORT_FILE" ]; then
            local port
            port=$(cat "$PORT_FILE")
            echo "running on port $port (PID $pid)"
        else
            echo "running (PID $pid, port unknown)"
        fi
        exit 0
    fi

    # Check for untracked jank processes
    local pid
    pid=$(pgrep -x jank 2>/dev/null || echo "")
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
