# janqua

A [Quarto](https://quarto.org) extension for evaluating [Jank](https://jank-lang.org) code blocks in documents.

Write Jank code in `.qmd` files and get live results — code output, inline SVG, Plotly charts, markdown tables, and more.

## Prerequisites

1. **Jank** — install from [jank-lang.org](https://jank-lang.org)
2. **Babashka** — install from [babashka.org](https://github.com/babashka/babashka#installation)
3. **bbin** — install from [github.com/babashka/bbin](https://github.com/babashka/bbin#installation)
4. **clj-nrepl-eval** — install via bbin:
   ```bash
   bbin install io.github.bhauman/clojure-mcp-light
   ```

Verify everything is available:
```bash
jank --version
bb --version
clj-nrepl-eval --help
```

## Install

```bash
quarto add scicloj/janqua
```

This installs the extension into `_extensions/jank/` in your project.

## Usage

Add the filter to your `.qmd` frontmatter:

```yaml
---
title: "My Document"
filters:
  - jank
---
```

Then write Jank code blocks:

````markdown
```{.jank}
(+ 1 2 3)
```
````

The filter automatically starts a Jank nREPL server if one isn't running.

### Output modes

| Syntax | Result |
|:-------|:-------|
| `` ```{.jank} `` | Code block (default) |
| `` ```{.jank output=html} `` | Raw HTML — SVG, Plotly charts, etc. |
| `` ```{.jank output=markdown} `` | Parsed markdown — tables, etc. |
| `` ```{.jank output=hidden} `` | Evaluate silently (no code, no output) |

### Additional attributes

| Attribute | Effect |
|:----------|:-------|
| `echo=false` | Hide the source code, show only the result |
| `eval=false` | Show code without evaluating it |

### Example: inline SVG

````markdown
```{.jank output=html}
(str "<svg width='100' height='100' xmlns='http://www.w3.org/2000/svg'>"
     "<circle cx='50' cy='50' r='40' fill='coral'/>"
     "</svg>")
```
````

### Example: markdown table

````markdown
```{.jank output=markdown}
(let [header "| x | x² |\n| --- | --- |"
      rows (map (fn [x] (str "| " x " | " (* x x) " |")) (range 1 6))]
  (clojure.string/join "\n" (cons header rows)))
```
````

## Managing the Jank process

The extension includes a lifecycle script for managing the Jank nREPL server:

```bash
# Check if jank is running
_extensions/jank/jank-lifecycle.sh status

# Start jank manually (the filter also does this automatically)
_extensions/jank/jank-lifecycle.sh start

# Stop jank when you're done
_extensions/jank/jank-lifecycle.sh stop
```

Jank starts automatically on the first render and persists across re-renders for fast iteration. Stop it explicitly when you're done working.

## Trying the example

After installing the extension, render the included example:

```bash
quarto render example.qmd --to html
```

Or use preview mode for live editing:

```bash
quarto preview example.qmd
```

## License

MIT
