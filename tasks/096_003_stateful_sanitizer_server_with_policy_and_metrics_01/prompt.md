I need a `Sanitizer` module built as a **GenServer** — I want one server process that cleans user input for us while keeping metrics across all the concurrent callers hitting it. Think of it as the stateful, process-based counterpart to a plain sanitizer: lots of client processes call into the single server, and the server serializes state updates so the counters aggregate safely.

Here's the API I need.

`Sanitizer.start_link(opts \\ [])` starts the server and returns `{:ok, pid}` on success. It should support two options: `:name`, an optional registered name — when it's given, I want to be able to reach the server through every function below by passing that name as `server`; and `:max_filename_length`, an integer defaulting to `255`, where filenames longer than that (after cleaning) get truncated down to that length.

`Sanitizer.sanitize_identifier(server, input)` cleans a SQL identifier. Keep only `[A-Za-z0-9_]`; if it comes out empty after stripping, return `{:error, :empty}`; if it starts with a digit, prepend `_`; otherwise `{:ok, cleaned}`.

`Sanitizer.sanitize_filename(server, input)` cleans a filename. Strip null bytes, strip `/` and `\`, keep only `[A-Za-z0-9_.-]`, collapse runs of 2+ dots down to one dot, and trim leading/trailing dots. If the result is empty → `{:error, :empty}`. Otherwise truncate to `:max_filename_length` if needed and return `{:ok, cleaned}`.

`Sanitizer.strip_html(server, input)` removes HTML. First remove `<script>…</script>` and `<style>…</style>` blocks **including their content** (case-insensitive, matching across newlines), then remove every remaining `<…>` tag while keeping the surrounding text. It returns `{:ok, cleaned, tags_stripped}`, where `tags_stripped` is the total number of `<…>` tag tokens present in the original input.

`Sanitizer.metrics(server)` returns the current metrics map with exactly these integer keys: `:identifiers`, `:identifiers_blocked`, `:filenames`, `:filenames_blocked`, `:filenames_truncated`, `:tags_stripped`, `:html_calls`.

`Sanitizer.reset_metrics(server)` zeros all the metrics and replies `:ok`.

For how the metrics move: every identifier call increments `:identifiers`, and if that call returned `{:error, :empty}` it also increments `:identifiers_blocked`. Every filename call increments `:filenames`; if it returned `{:error, :empty}` it also increments `:filenames_blocked`; and if it was truncated (meaning the cleaned length was strictly greater than `:max_filename_length`) it also increments `:filenames_truncated`. Every `strip_html` call increments `:html_calls` and adds the stripped tag count to `:tags_stripped`.

Since a GenServer serializes calls, I expect the metrics to be exact even when hundreds of processes are calling concurrently. Standard library only, please — no external dependencies.
