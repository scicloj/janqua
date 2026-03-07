-- Quarto Lua filter for evaluating Jank code blocks via nREPL.
--
-- Usage in .qmd frontmatter:
--   filters:
--     - jank
--
-- Port is resolved automatically (no config needed).
--
-- Code block options:
--   ```{.jank}                — evaluate, show code + result as code block
--   ```{.jank output=html}    — evaluate, render result as raw HTML (SVG, Plotly, etc.)
--   ```{.jank output=markdown} — evaluate, render result as markdown (tables, etc.)
--   ```{.jank output=hidden}  — evaluate silently (no code, no output)
--   ```{.jank eval=false}     — show code only, don't evaluate
--   ```{.jank echo=false}     — evaluate but hide the code

local jank_port = nil

-- Check whether a port is actually reachable (TCP connect test).
-- Uses bash /dev/tcp (works on Linux and macOS with bash 3+).
local function port_reachable(port)
  local ok = os.execute(
    "bash -c 'echo > /dev/tcp/127.0.0.1/" .. port .. "' 2>/dev/null"
  )
  return ok == true or ok == 0
end

-- Read a port from a file, returns string or nil.
local function read_port_file(path)
  local f = io.open(path, "r")
  if f then
    local port = f:read("*l")
    f:close()
    if port and port:match("^%d+$") then
      return port
    end
  end
  return nil
end

-- Discover jank nREPL port from a running jank process.
-- Uses lsof (cross-platform) with ss as fallback (Linux).
local function discover_port_from_process()
  -- Try lsof first (works on Linux and macOS)
  local handle = io.popen(
    [[lsof -iTCP -sTCP:LISTEN -nP 2>/dev/null | awk '/jank.*LISTEN/ {split($NF, a, ":"); print a[2]}' | head -1]]
  )
  local port = handle:read("*l")
  handle:close()
  if port and port:match("^%d+$") then
    return port
  end

  -- Fallback: ss (Linux only)
  handle = io.popen(
    [[ss -tlnp 2>/dev/null | grep '"jank"' | awk '{print $4}' | awk -F: '{print $NF}' | head -1]]
  )
  port = handle:read("*l")
  handle:close()
  if port and port:match("^%d+$") then
    return port
  end

  return nil
end

-- Resolve the path to jank-lifecycle.sh (sibling of this filter script).
local function lifecycle_script()
  local script = PANDOC_SCRIPT_FILE
  local dir = script:match("(.*[/\\])") or "./"
  return dir .. "jank-lifecycle.sh"
end

-- Check if a PID is alive via kill -0.
local function pid_alive(pid)
  local ok = os.execute("kill -0 " .. pid .. " 2>/dev/null")
  return ok == true or ok == 0
end

-- Read PID from .jank-pid file, returns string or nil.
local function read_pid_file()
  return read_port_file(".jank-pid")  -- same format: single number on a line
end

-- Start jank repl via lifecycle script and return the port.
local function auto_start_jank()
  io.stderr:write("[jank filter] No running Jank found. Starting via lifecycle script...\n")

  local handle = io.popen(lifecycle_script() .. " start 2>/dev/null")
  local port = handle:read("*l")
  handle:close()

  if port and port:match("^%d+$") then
    io.stderr:write("[jank filter] Jank started on port " .. port .. "\n")
    return port
  end

  io.stderr:write("[jank filter] ERROR: Failed to start jank. Run: " .. lifecycle_script() .. " start\n")
  return nil
end

-- Resolve the Jank nREPL port using the discovery chain.
-- Each candidate port is validated before use; stale ports are skipped.
local function resolve_port(meta)
  -- 1. Explicit port in frontmatter
  if meta and meta.jank then
    local port = meta.jank.port
    if port then
      port = pandoc.utils.stringify(port)
      if port_reachable(port) then return port end
      io.stderr:write("[jank filter] Port " .. port .. " from frontmatter is not reachable, trying next.\n")
    end
  end

  -- 2. PID file + port file (managed by lifecycle script)
  local pid = read_pid_file()
  if pid and pid_alive(pid) then
    local port = read_port_file(".jank-nrepl-port")
    if port and port_reachable(port) then return port end
  end

  -- 3. Environment variable
  local env_port = os.getenv("JANK_PORT")
  if env_port and env_port ~= "" then
    if port_reachable(env_port) then return env_port end
    io.stderr:write("[jank filter] Port " .. env_port .. " from JANK_PORT is not reachable, trying next.\n")
  end

  -- 4. Process discovery via ss
  local port = discover_port_from_process()
  if port then return port end

  -- 5. Auto-start via lifecycle script
  return auto_start_jank()
end

-- Unquote a Clojure string value: strip outer quotes and unescape.
local function unquote_clj_string(s)
  if not s then return nil end
  -- Strip surrounding quotes
  s = s:match('^"(.*)"$') or s
  -- Unescape Clojure string escapes
  s = s:gsub('\\\\', '\0BACKSLASH\0')  -- protect escaped backslashes
  s = s:gsub('\\"', '"')
  s = s:gsub('\\n', '\n')
  s = s:gsub('\\t', '\t')
  s = s:gsub('\0BACKSLASH\0', '\\')    -- restore backslashes
  return s
end

-- Evaluate Jank code via clj-nrepl-eval.
-- Returns: value string, stdout string (may be nil), error string (may be nil)
local function eval_jank(code)
  if not jank_port then
    return nil, nil, "Jank nREPL port not available. Could not discover or start Jank."
  end

  local escaped = code:gsub("'", "'\\''")
  local cmd = "clj-nrepl-eval -p " .. jank_port .. " '" .. escaped .. "' 2>&1"
  local handle = io.popen(cmd)
  local raw = handle:read("*a")
  handle:close()

  if raw:match("ConnectException") or raw:match("Connection refused") then
    return nil, nil, "Cannot connect to Jank nREPL on port " .. jank_port .. ". Is `jank repl` running?"
  end

  local lines = {}
  for line in raw:gmatch("[^\n]+") do
    table.insert(lines, line)
  end

  local stdout_lines = {}
  local value = nil

  for _, line in ipairs(lines) do
    if line:match("^=> ") then
      value = line:sub(4)
    elseif line:match("^%*========") then
      -- skip footer
    elseif value == nil then
      table.insert(stdout_lines, line)
    end
  end

  local stdout = nil
  if #stdout_lines > 0 then
    stdout = table.concat(stdout_lines, "\n")
  end

  return value, stdout, nil
end

-- Extract the Jank port from document metadata.
function Meta(meta)
  jank_port = resolve_port(meta)
  if not jank_port then
    io.stderr:write("[jank filter] WARNING: No Jank nREPL port available.\n")
  end
end

-- Process Jank code blocks.
function CodeBlock(el)
  if not el.classes:includes("jank") then
    return nil
  end

  local code = el.text
  local output_mode = el.attributes["output"] or "code"
  local echo = el.attributes["echo"] ~= "false"
  local eval = el.attributes["eval"] ~= "false"

  -- output=hidden implies both echo=false and suppressed output
  if output_mode == "hidden" then
    echo = false
  end

  local blocks = {}

  -- Show code (as clojure for syntax highlighting)
  if echo then
    table.insert(blocks, pandoc.CodeBlock(code, pandoc.Attr("", {"clojure"})))
  end

  -- Evaluate
  if eval then
    local value, stdout, err = eval_jank(code)

    if err then
      table.insert(blocks, pandoc.Div(
        pandoc.CodeBlock(err, pandoc.Attr("", {"error"})),
        pandoc.Attr("", {"cell-output", "cell-output-error"})
      ))
    elseif output_mode == "hidden" then
      -- Evaluate but show nothing
    elseif output_mode == "html" then
      -- Stdout as code block if present
      if stdout then
        table.insert(blocks, pandoc.Div(
          pandoc.CodeBlock(stdout),
          pandoc.Attr("", {"cell-output", "cell-output-stdout"})
        ))
      end
      -- Value as raw HTML
      if value then
        local html = unquote_clj_string(value)
        table.insert(blocks, pandoc.RawBlock("html", html))
      end
    elseif output_mode == "markdown" then
      -- Stdout as code block if present
      if stdout then
        table.insert(blocks, pandoc.Div(
          pandoc.CodeBlock(stdout),
          pandoc.Attr("", {"cell-output", "cell-output-stdout"})
        ))
      end
      -- Value as markdown
      if value then
        local md = unquote_clj_string(value)
        local doc = pandoc.read(md, "markdown")
        for _, block in ipairs(doc.blocks) do
          table.insert(blocks, block)
        end
      end
    else
      -- Default: code output
      local output_parts = {}
      if stdout then
        table.insert(output_parts, stdout)
      end
      if value then
        table.insert(output_parts, value)
      end
      if #output_parts > 0 then
        table.insert(blocks, pandoc.Div(
          pandoc.CodeBlock(table.concat(output_parts, "\n")),
          pandoc.Attr("", {"cell-output", "cell-output-stdout"})
        ))
      end
    end
  end

  return blocks
end

-- Ensure Meta runs before CodeBlock.
return {
  { Meta = Meta },
  { CodeBlock = CodeBlock }
}
