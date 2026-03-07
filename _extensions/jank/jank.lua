-- Quarto Lua filter for evaluating Jank code blocks via nREPL.
--
-- Usage in .qmd frontmatter:
--   filters:
--     - jank
--
-- Port is resolved automatically (no config needed).
--
-- Code block options (use {clojure .jank} for editor syntax highlighting):
--   ```{clojure .jank}                — evaluate, show code + result as code block
--   ```{clojure .jank output=html}    — evaluate, render result as raw HTML (SVG, Plotly, etc.)
--   ```{clojure .jank output=markdown} — evaluate, render result as markdown (tables, etc.)
--   ```{clojure .jank output=hidden}  — evaluate silently (no code, no output)
--   ```{clojure .jank eval=false}     — show code only, don't evaluate
--   ```{clojure .jank echo=false}     — evaluate but hide the code
--
-- Kindly convention:
--   ^:kind/hiccup [:div ...]  — auto-converts hiccup to HTML
--   ^:kind/html "..."         — renders string as raw HTML (on metadata-capable values)
--   ^:kind/hidden [...]       — suppresses output (code still shown)

local jank_port = nil

-- Shell-escape a string for use inside single quotes.
-- Replaces ' with '\'' (end quote, escaped quote, reopen quote).
local function shell_quote(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

-- Check whether a port is actually reachable (TCP connect test).
-- Uses bash /dev/tcp (works on Linux and macOS with bash 3+).
-- Port must be validated as numeric before calling this function.
local function port_reachable(port)
  local ok = os.execute(
    "bash -c 'echo > /dev/tcp/127.0.0.1/" .. port .. "' 2>/dev/null"
  )
  return ok == true or ok == 0
end

-- Read a single number from a file (used for PID and port files).
-- Returns the number as a string, or nil if the file is missing/corrupt.
local function read_number_file(path)
  local f = io.open(path, "r")
  if f then
    local content = f:read("*l")
    f:close()
    if content and content:match("^%d+$") then
      return content
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
-- PID must be validated as numeric before calling this function.
local function pid_alive(pid)
  local ok = os.execute("kill -0 " .. shell_quote(pid) .. " 2>/dev/null")
  return ok == true or ok == 0
end

-- Start jank repl via lifecycle script and return the port.
local function auto_start_jank()
  io.stderr:write("[jank filter] No running Jank found. Starting via lifecycle script...\n")

  local cmd = shell_quote(lifecycle_script()) .. " start 2>/dev/null"
  local handle = io.popen(cmd)
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
      if port:match("^%d+$") and port_reachable(port) then return port end
      io.stderr:write("[jank filter] Port " .. port .. " from frontmatter is not reachable, trying next.\n")
    end
  end

  -- 2. PID file + port file (managed by lifecycle script)
  local pid = read_number_file(".jank-pid")
  if pid and pid_alive(pid) then
    local port = read_number_file(".jank-nrepl-port")
    if port and port_reachable(port) then return port end
  end

  -- 3. Environment variable
  local env_port = os.getenv("JANK_PORT")
  if env_port and env_port:match("^%d+$") then
    if port_reachable(env_port) then return env_port end
    io.stderr:write("[jank filter] Port " .. env_port .. " from JANK_PORT is not reachable, trying next.\n")
  end

  -- 4. Process discovery via lsof/ss
  -- NOTE: This finds any jank process, not just this project's. If multiple
  -- projects run jank simultaneously, this could connect to the wrong session.
  -- Steps 1-3 above are project-specific and preferred.
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
  s = s:gsub('\\r', '\r')
  s = s:gsub('\0BACKSLASH\0', '\\')    -- restore backslashes
  return s
end


-- Jank code to bootstrap janqua helpers (sent on first connection).
-- NOTE: janqua-hiccup->html does not escape HTML special characters in
-- attribute values or text content. This is acceptable for a document
-- authoring tool where the user controls the code, but means hiccup
-- with untrusted data could produce malformed HTML.
local janqua_bootstrap = [=[
(defn janqua-hiccup->html [form]
  (cond
    (string? form) form
    (number? form) (str form)
    (vector? form)
    (let [tag (name (first form))
          has-attrs (map? (second form))
          attrs (if has-attrs (second form) {})
          children (if has-attrs (drop 2 form) (rest form))
          attr-str (apply str
                     (map (fn [[k v]]
                            (str " " (name k) "=\"" v "\""))
                          attrs))]
      (str "<" tag attr-str ">"
           (apply str (map janqua-hiccup->html children))
           "</" tag ">"))
    :else (str form)))
]=]

local janqua_bootstrapped = false

-- Send raw code to Jank via clj-nrepl-eval.
-- Returns: raw output string, error string (may be nil)
local function eval_jank_raw(code)
  if not jank_port then
    return nil, "Jank nREPL port not available. Could not discover or start Jank."
  end

  local cmd = "clj-nrepl-eval -p " .. shell_quote(jank_port) .. " --timeout 10000 " .. shell_quote(code) .. " 2>&1"
  local handle = io.popen(cmd)
  local raw = handle:read("*a")
  handle:close()

  if raw:match("ConnectException") or raw:match("Connection refused") then
    return nil, "Cannot connect to Jank nREPL on port " .. jank_port .. ". Is `jank repl` running?"
  end

  return raw, nil
end

-- Parse clj-nrepl-eval output into value + stdout.
local function parse_nrepl_output(raw)
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

  return value, stdout
end

-- Bootstrap janqua helpers in the Jank session (once).
local function ensure_bootstrap()
  if janqua_bootstrapped then return end
  local raw, err = eval_jank_raw(janqua_bootstrap)
  if err then
    io.stderr:write("[jank filter] WARNING: Failed to bootstrap janqua helpers: " .. err .. "\n")
    return
  end
  janqua_bootstrapped = true
end

-- Wrap user code to extract Kindly metadata from the result.
-- Uses fn call instead of let to work around a Jank bug where let bindings
-- lose reader-attached metadata (e.g. ^:kind/hiccup).
local function wrap_with_kindly(code)
  return '((fn [v__janqua]'
    .. ' ((fn [m__janqua]'
    .. ' ((fn [kind__janqua]'
    .. ' {:janqua/kind kind__janqua'
    .. ' :janqua/value (pr-str'
    .. ' (if (or (get-in m__janqua [:kindly/options :wrapped-value])'
    .. '         (and (#{:kind/html :kind/md :kind/markdown} kind__janqua)'
    .. '              (vector? v__janqua)))'
    .. '   (first v__janqua) v__janqua))})'
    .. ' (when m__janqua'
    .. ' (or (:kindly/kind m__janqua)'
    .. ' (some (fn [k] (when (and (keyword? k) (= (namespace k) "kind") (get m__janqua k)) k))'
    .. ' (keys m__janqua))))))'
    .. ' (meta v__janqua)))'
    .. ' (do ' .. code .. '))'
end

-- Parse the wrapper response to extract kind and value.
local function parse_kindly_response(value_str)
  if not value_str then return nil, nil end

  -- Match :janqua/kind value
  local kind = value_str:match(":janqua/kind (:kind/[%w_-]+)")

  -- Match :janqua/value — everything between :janqua/value and the final }
  local raw_value = value_str:match(":janqua/value (.+)}%s*$")

  return kind, raw_value
end

-- Evaluate Jank code via clj-nrepl-eval with Kindly wrapper.
-- Returns: value string, stdout string, error string, kind string (all may be nil)
local function eval_jank(code)
  ensure_bootstrap()

  local wrapped = wrap_with_kindly(code)
  local raw, err = eval_jank_raw(wrapped)
  if err then return nil, nil, err, nil end

  local value, stdout = parse_nrepl_output(raw)

  -- If the wrapper map wasn't returned, the code likely threw an error.
  -- The raw value IS the error message in that case.
  if value and not value:match(":janqua/kind") then
    return nil, stdout, value, nil
  end

  local kind, actual_value = parse_kindly_response(value)

  -- Unquote the pr-str serialization layer from the wrapper
  actual_value = unquote_clj_string(actual_value)

  return actual_value, stdout, nil, kind
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

  -- Evaluate first so Kindly metadata can influence echo/output_mode
  local value, stdout, err, kind = nil, nil, nil, nil
  if eval then
    value, stdout, err, kind = eval_jank(code)

    -- Kindly metadata overrides the output= attribute
    if kind then
      if kind == ":kind/hiccup" then
        -- Convert hiccup to HTML via a second eval
        local html_raw, html_err = eval_jank_raw("(janqua-hiccup->html " .. unquote_clj_string(value) .. ")")
        if not html_err then
          local html_value = parse_nrepl_output(html_raw)
          if html_value then
            value = html_value
          end
        end
        output_mode = "html"
      elseif kind == ":kind/html" then
        output_mode = "html"
      elseif kind == ":kind/md" or kind == ":kind/markdown" then
        output_mode = "markdown"
      elseif kind == ":kind/hidden" then
        output_mode = "hidden"
      end
    end
  end

  local blocks = {}

  -- Show code (as clojure for syntax highlighting)
  if echo then
    table.insert(blocks, pandoc.CodeBlock(code, pandoc.Attr("", {"clojure"})))
  end

  -- Render output
  if eval then
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
          pandoc.CodeBlock(table.concat(output_parts, "\n"), pandoc.Attr("", {"clojure"})),
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
