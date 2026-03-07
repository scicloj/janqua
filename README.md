# janqua

A [Quarto](https://quarto.org) extension for evaluating [Jank](https://jank-lang.org) code blocks in documents.

Write Jank code in `.qmd` files and get live results — code output, inline SVG, Plotly charts, markdown tables, and more. Uses the [Kindly](https://scicloj.github.io/kindly-noted/) convention for rendering, compatible with the Clojure ecosystem.

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

### Rendering with Kindly

Annotate values with Kindly metadata to control how they render:

| Kind | Usage | Effect |
|:-----|:------|:-------|
| `:kind/hiccup` | `^:kind/hiccup [:div "hello"]` | Converts hiccup to HTML |
| `:kind/html` | `^:kind/html ["<b>bold</b>"]` | Renders string as raw HTML |
| `:kind/md` | `^:kind/md ["# Title"]` | Renders string as markdown |
| `:kind/hidden` | `^:kind/hidden [expr]` | Evaluates but hides the result |

For `:kind/html` and `:kind/md`, wrap string expressions in a vector
(strings can't hold metadata):

````markdown
```{.jank}
^:kind/hiccup
[:svg {:width "100" :height "100" :xmlns "http://www.w3.org/2000/svg"}
  [:circle {:cx "50" :cy "50" :r "40" :fill "coral"}]]
```

```{.jank}
^:kind/html
[(str "<b>" "computed" "</b>")]
```

```{.jank}
^:kind/md
[(str "| a | b |\n| --- | --- |\n| 1 | 2 |")]
```
````

The long form `^{:kindly/kind :kind/hiccup}` also works.

### Additional attributes

| Attribute | Effect |
|:----------|:-------|
| `echo=false` | Hide the source code, show only the result |
| `eval=false` | Show code without evaluating it |

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
