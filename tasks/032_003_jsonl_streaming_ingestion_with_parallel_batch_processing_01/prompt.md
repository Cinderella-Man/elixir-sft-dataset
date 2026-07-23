Hey — could you put together an Elixir module for me called `JsonlIngestion`? What I need is something that streams a JSONL (JSON Lines) file line by line, processes the records in batches, and upserts each batch into a database table through Ecto — and I want the option to do that in parallel.

For the public API, I'm after these functions. The main entry point is `JsonlIngestion.ingest(repo, schema, file_path, opts \\ [])`. It should stream the file at `file_path` one line at a time using `File.stream!/1`, parse each line with `Jason.decode/1`, skip blank lines, collect the parsed records into batches, and insert each batch via `repo.insert_all/3`. I need it to return `{:ok, stats}` on success or `{:error, reason}` on failure. That `stats` value is a map with exactly these four integer keys and no others:
- `:total` — total non-blank lines encountered in the file (this includes lines that were later skipped)
- `:inserted` — records successfully inserted / upserted, as reported by the count `insert_all` returns
- `:skipped` — individual lines that could not be parsed as valid JSON objects (malformed JSON or non-object JSON values like arrays, strings, numbers)
- `:failed` — records in batches where `insert_all` raised an error

For the accepted `opts`, here's what I want:
- `:batch_size` (integer, default 500) — how many successfully parsed records to collect before calling `insert_all`
- `:on_conflict` (atom or keyword, default `:replace_all`) — passed directly to `Repo.insert_all` as the `on_conflict:` option
- `:conflict_target` (atom or list, default `:nothing`) — passed as `conflict_target:`
- `:max_concurrency` (integer, default 1) — when > 1, insert batches in parallel using `Task.async_stream` with the given concurrency. When 1, process batches sequentially with `Enum.reduce`.
- `:timeout` (integer, default 30_000) — per-batch timeout in milliseconds, used as the `:timeout` option for `Task.async_stream`

The reason I want the file read with `File.stream!/1` rather than `File.read!/1` is so lines get pulled from disk lazily instead of reading the whole raw file in one call. So build it as a streaming pipeline:
1. `File.stream!(path)` to get a lazy line stream
2. `Stream.reject/2` to drop blank lines (after trimming)
3. Parse each line with `Jason.decode/1`; lines that fail or decode to non-map values are counted as `:skipped` (emit a Logger.warning)
4. Collect successfully parsed maps
5. Chunk into batches of `:batch_size`
6. Insert each batch (sequentially or in parallel depending on `:max_concurrency`)

Before insertion, convert the string-keyed JSON maps to atom-keyed maps using only fields declared on the schema (via `schema.__schema__(:fields)`), and inject `inserted_at` / `updated_at` timestamps if the schema declares them.

One thing I care about a lot: the module has to handle these error conditions gracefully and never raise:
- File not found → `{:error, :file_not_found}`
- File exists but is completely empty (0 non-blank lines) — this is valid, return `{:ok, stats}` with all zeroes, i.e. `{:ok, %{total: 0, inserted: 0, skipped: 0, failed: 0}}`
- An individual line fails JSON parsing → count as `:skipped`, continue
- A batch `insert_all` call fails → log the error, add the batch size to `:failed`, and continue with the remaining batches

Use `File.exists?/1`, `File.stream!/1`, and `Jason.decode/1` for the I/O and parsing. Use `require Logger` and emit a `Logger.info/1` line after every batch with the running totals.

Can you give me the complete module in a single file? Assume Jason and Ecto are available as dependencies; don't add anything else.
