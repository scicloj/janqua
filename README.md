# Janqua

A [Quarto](https://quarto.org) extension for evaluating [Jank](https://jank-lang.org) code blocks in documents.

Write Jank code in `.qmd` files and get live results — code output, inline SVG, Plotly charts, markdown tables, and more. Uses the [Kindly](https://scicloj.github.io/kindly-noted/) convention for rendering, compatible with the Clojure ecosystem.

## What is Quarto?

[Quarto](https://quarto.org) is an open-source publishing system for technical documents. You write `.qmd` (Quarto Markdown) files mixing prose and code, and Quarto renders them to HTML, PDF, slides, and other formats.

Quarto supports several project types:

- **Single documents** — a standalone `.qmd` file rendered to HTML
- **[Websites](https://quarto.org/docs/websites/)** — multiple pages with navigation, like a documentation site
- **[Books](https://quarto.org/docs/books/)** — chapters rendered as a navigable book

### Quarto in the Clojure community

[Clay](https://scicloj.github.io/clay) is a Clojure tool for data visualization and literate programming. Clay can generate Quarto markdown from Clojure namespaces, then use Quarto as a rendering engine to produce HTML pages, books, and slideshows. [Clojure Civitas](https://clojurecivitas.org/), the community blog, is built this way.

janqua brings a similar experience to [Jank](https://jank-lang.org): you write Jank code directly in `.qmd` files, and the Quarto filter evaluates it during rendering.

## Prerequisites

1. **[Quarto](https://quarto.org/docs/get-started/)** — the publishing system
2. **[Jank](https://jank-lang.org)** — the Jank compiler and REPL
3. **[Babashka](https://github.com/babashka/babashka#installation)** — fast Clojure scripting runtime
4. **[bbin](https://github.com/babashka/bbin#installation)** — tool installer for Babashka
5. **clj-nrepl-eval** — nREPL client (install via bbin):
   ```bash
   bbin install io.github.bhauman/clojure-mcp-light
   ```

Verify everything is available:
```bash
quarto --version
jank --version
bb --version
clj-nrepl-eval --help
```

## Getting started

### 1. Create a project directory

```bash
mkdir my-jank-doc
cd my-jank-doc
```

### 2. Install the extension

Run this **inside your project directory** — it creates an `_extensions/` folder there:

```bash
quarto add scicloj/janqua
```

### 3. Write a document

Create a file called `hello.qmd`:

````markdown
---
title: "Hello Jank"
filters:
  - jank
---

```{.jank}
(+ 1 2 3)
```

```{.jank}
^:kind/hiccup
[:div {:style "color: coral; font-size: 24px;"} "Hello from Jank!"]
```
````

### 4. Render it

```bash
quarto render hello.qmd
```

This starts a Jank nREPL server (if one isn't already running), evaluates the code blocks, and produces `hello.html`.

## Rendering workflow

**`quarto render`** — renders the document once and exits. Use this for final output.

```bash
quarto render hello.qmd            # produces hello.html
quarto render hello.qmd --to pdf   # produces hello.pdf
```

**`quarto preview`** — starts a local web server and re-renders automatically when you save the `.qmd` file. Use this while writing:

```bash
quarto preview hello.qmd
```

This opens a browser with live preview. Edit your `.qmd`, save, and the page refreshes with updated results. Press Ctrl-C to stop.

The Jank nREPL server starts on the first render and stays running for fast re-evaluation. Stop it when you're done:

```bash
_extensions/jank/jank-lifecycle.sh stop
```

## Kindly annotations

Annotate values with [Kindly](https://scicloj.github.io/kindly-noted/) metadata to control rendering. Without an annotation, results display as code output.

### `^:kind/hiccup` — HTML from data

Converts a [hiccup](https://github.com/weavejester/hiccup) vector to HTML:

````markdown
```{.jank}
^:kind/hiccup
[:svg {:width "100" :height "100" :xmlns "http://www.w3.org/2000/svg"}
  [:circle {:cx "50" :cy "50" :r "40" :fill "coral"}]]
```
````

### `^:kind/html` — raw HTML

Renders a string as raw HTML. Wrap the expression in a vector (strings can't hold metadata):

````markdown
```{.jank}
^:kind/html
[(str "<b>bold</b> and <em>italic</em>")]
```
````

### `^:kind/md` — markdown

Renders a string as markdown:

````markdown
```{.jank}
^:kind/md
[(str "| a | b |\n| --- | --- |\n| 1 | 2 |")]
```
````

### `^:kind/hidden` — suppress output

Evaluates the code but hides the result (code is still shown). Useful for setup:

````markdown
```{.jank}
^:kind/hidden
[(def my-data [1 2 3])]
```
````

### Long form

The shorthand `^:kind/hiccup` is equivalent to `^{:kindly/kind :kind/hiccup}`:

````markdown
```{.jank}
^{:kindly/kind :kind/hiccup}
[:div "hello"]
```
````

## Code block attributes

| Attribute | Effect |
|:----------|:-------|
| `echo=false` | Hide the source code, show only the result |
| `eval=false` | Show code without evaluating it |

## Managing the Jank process

```bash
_extensions/jank/jank-lifecycle.sh status   # check if running
_extensions/jank/jank-lifecycle.sh start    # start manually
_extensions/jank/jank-lifecycle.sh stop     # stop when done
```

## License

MIT
