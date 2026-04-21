Write me an Elixir module called `JsonlIngestion` that streams a JSONL
(JSON Lines) file line by line, processes records in batches, and upserts each
batch into a database table via Ecto — optionally in parallel.

I need these functions in the public API:

- `JsonlIngestion.ingest(repo, schema, file_path, opts \\ [])` — the main
  entry point. It streams the file at `file_path` one line at a time using
  `File.stream!/1`, parses each line with `Jason.decode/1`, skips blank lines,
  collects parsed records into batches, and inserts each batch via
  `repo.insert_all/3`. It must return `{:ok, stats}` on success or
  `{:error, reason}` on failure.
  `stats` is a map with these integer keys:
    - `:total`    — total non-blank lines encountered in the file
    - `:inserted` — records successfully inserted / upserted
    - `:skipped`  — individual lines that could not be parsed as valid JSON
                    objects (malformed JSON or non-object JSON values like
                    arrays, strings, numbers)
    - `:failed`   — records in batches where `insert_all` raised an error

- Accepted `opts`:
    - `:batch_size` (integer, default 500) — how many successfully parsed
      records to collect before calling `insert_all`
    - `:on_conflict` (atom or keyword, default `:replace_all`) — passed
      directly to `Repo.insert_all` as the `on_conflict:` option
    - `:conflict_target` (atom or list, default `:nothing`) — passed as
      `conflict_target:`
    - `:max_concurrency` (integer, default 1) — when > 1, insert batches
      in parallel using `Task.async_stream` with the given concurrency.
      When 1, process batches sequentially with `Enum.reduce`.
    - `:timeout` (integer, default 30_000) — per-batch timeout in
      milliseconds, used as the `:timeout` option for `Task.async_stream`

Because the file is streamed line-by-line with `File.stream!/1`, the module
must never load the entire file into memory. Build a streaming pipeline:

1. `File.stream!(path)` to get a lazy line stream
2. `Stream.reject/2` to drop blank lines (after trimming)
3. Parse each line with `Jason.decode/1`; lines that fail or decode to
   non-map values are counted as `:skipped` (emit a Logger.warning)
4. Collect successfully parsed maps
5. Chunk into batches of `:batch_size`
6. Insert each batch (sequentially or in parallel depending on
   `:max_concurrency`)

Before insertion, convert string-keyed JSON maps to atom-keyed maps using
only fields declared on the schema (via `schema.__schema__(:fields)`), and
inject `inserted_at` / `updated_at` timestamps if the schema declares them.

The module must handle these error conditions gracefully — never raise:
- File not found → `{:error, :file_not_found}`
- File exists but is completely empty (0 non-blank lines) — this is valid,
  return `{:ok, stats}` with all zeroes
- An individual line fails JSON parsing → count as `:skipped`, continue
- A batch `insert_all` call fails → log the error, add the batch size to
  `:failed`, and continue with the remaining batches

Use `File.exists?/1`, `File.stream!/1`, and `Jason.decode/1` for I/O and
parsing. Use `require Logger` and emit a `Logger.info/1` line after every
batch with the running totals.

Give me the complete module in a single file. Assume Jason and Ecto are
available as dependencies; do not add anything else.