# Janqua

A [Quarto](https://quarto.org) extension for evaluating [Jank](https://jank-lang.org) code blocks in documents.

Write Jank code in `.qmd` files and get live results — code output, SVG, charts (Plotly, Vega-Lite, etc.), diagrams (Mermaid, Graphviz), markdown tables, and more. Uses the [Kindly](https://scicloj.github.io/kindly-noted/) convention for rendering, compatible with the Clojure ecosystem.

> **Experimental** — this project is at an early stage. Feedback and ideas are welcome via [GitHub issues](https://github.com/scicloj/janqua/issues) or the [Scicloj Zulip chat](https://scicloj.github.io/docs/community/chat/).

**[Read the documentation →](https://scicloj.github.io/janqua)**

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

## Prerequisites

- [Quarto](https://quarto.org/docs/get-started/)
- [Jank](https://jank-lang.org)
- [Babashka](https://github.com/babashka/babashka#installation) + [bbin](https://github.com/babashka/bbin#installation)
- clj-nrepl-eval: `bbin install https://github.com/bhauman/clojure-mcp-light.git --tag v0.2.1 --as clj-nrepl-eval --main-opts '["-m" "clojure-mcp-light.nrepl-eval"]'`

## License

MIT
