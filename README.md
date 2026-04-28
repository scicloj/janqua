# Janqua

A [Quarto](https://quarto.org) extension that brings [Jank](https://jank-lang.org) to interactive data visualization, documentation, and research reports.

Write Jank code in `.qmd` files and get live results — code output, SVG, charts (Plotly, Vega-Lite, etc.), diagrams (Mermaid, Graphviz), markdown tables, and more. Uses the [Kindly](https://scicloj.github.io/kindly-noted/) convention for rendering (partial coverage at this stage).

Quarto is widely used in scientific communities for technical writing, and has been used in multiple Clojure projects, most often through [Clay](https://scicloj.github.io/clay/). Janqua brings this publishing experience to the Jank community — and lets Jank developers share posts on [Clojure Civitas](https://clojurecivitas.github.io/), the Clojure community's collaborative space.

> **Experimental** — this project is at an early stage. Currently tested only on Linux; macOS is unverified. Feedback and ideas are welcome via [GitHub issues](https://github.com/scicloj/janqua/issues) or the [Scicloj Zulip chat](https://scicloj.github.io/docs/community/chat/).

**[Read the documentation →](https://scicloj.github.io/janqua)**

## Prerequisites

- [Quarto](https://quarto.org/docs/get-started/)
- [Jank](https://jank-lang.org)
- [Babashka](https://github.com/babashka/babashka#installation) + [bbin](https://github.com/babashka/bbin#installation)
- `clj-nrepl-eval` — provided by [clojure-mcp-light](https://github.com/bhauman/clojure-mcp-light); install via bbin:

  ```bash
  bbin install io.github.bhauman/clojure-mcp-light
  ```

## Quick start

Install the extension in your project:

```bash
quarto add scicloj/janqua
```

Create `hello.qmd`:

````markdown
---
title: "Hello Jank"
filters:
  - jank
---

```{.clojure .jank}
(+ 1 2 3)
```

```{.clojure .jank}
^:kind/hiccup
[:div {:style "color: coral; font-size: 24px;"} "Hello from Jank!"]
```
````

Render it:

```bash
quarto render hello.qmd
```

Or use live preview:

```bash
quarto preview hello.qmd
```

A Jank nREPL is auto-started on first render and kept alive for fast re-evaluation. Stop it when you're done:

```bash
_extensions/jank/jank-lifecycle.sh stop
```

See [Getting Started](https://scicloj.github.io/janqua/getting-started.html) for details.

## License

MIT
