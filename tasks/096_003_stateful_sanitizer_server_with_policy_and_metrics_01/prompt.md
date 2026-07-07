Write me an Elixir module called `Sanitizer` implemented as a **GenServer** that sanitizes user input while tracking metrics across concurrent callers. This is the stateful, process-based counterpart of a plain sanitizer: many client processes call into one server, which serializes state updates and aggregates counters safely.

Public API:

- `Sanitizer.start_link(opts \\ [])` — start the server. Supported options:
  - `:name` — optional registered name.
  - `:max_filename_length` — integer, default `255`. Filenames longer than this (after cleaning) are truncated to this length.

- `Sanitizer.sanitize_identifier(server, input)` — clean a SQL identifier. Keep only `[A-Za-z0-9_]`; if empty after stripping return `{:error, :empty}`; if it starts with a digit prepend `_`; otherwise `{:ok, cleaned}`.

- `Sanitizer.sanitize_filename(server, input)` — clean a filename. Strip null bytes, strip `/` and `\`, keep only `[A-Za-z0-9_.-]`, collapse runs of 2+ dots to one dot, trim leading/trailing dots. Empty result → `{:error, :empty}`. Otherwise truncate to `:max_filename_length` if needed and return `{:ok, cleaned}`.

- `Sanitizer.strip_html(server, input)` — remove HTML. First remove `<script>…</script>` and `<style>…</style>` blocks **including their content** (case-insensitive, across newlines), then remove every remaining `<…>` tag, keeping surrounding text. Return `{:ok, cleaned, tags_stripped}` where `tags_stripped` is the total number of `<…>` tag tokens present in the original input.

- `Sanitizer.metrics(server)` — return the current metrics map with these integer keys: `:identifiers`, `:identifiers_blocked`, `:filenames`, `:filenames_blocked`, `:filenames_truncated`, `:tags_stripped`, `:html_calls`.

- `Sanitizer.reset_metrics(server)` — zero all metrics; reply `:ok`.

Metric rules:
- Every identifier call increments `:identifiers`; if it returned `{:error, :empty}` also increment `:identifiers_blocked`.
- Every filename call increments `:filenames`; if it returned `{:error, :empty}` also increment `:filenames_blocked`; if it was truncated also increment `:filenames_truncated`.
- Every `strip_html` call increments `:html_calls` and adds the stripped tag count to `:tags_stripped`.

Because a GenServer serializes calls, metrics must be exact even when hundreds of processes call concurrently. Standard library only — no external dependencies.