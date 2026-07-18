Write me an Elixir module called `DataIngestion` that reads a large JSON array
file, processes it in batches, and upserts each batch into a database table via
Ecto.

I need these functions in the public API:

- `DataIngestion.ingest(repo, schema, file_path, opts \\ [])` — the main entry
  point. It reads the JSON file at `file_path`, splits the decoded list into
  batches, and calls `repo.insert_all/3` for each batch. It must return
  `{:ok, stats}` on success or `{:error, reason}` on failure.
  `stats` is a map with these integer keys:
    - `:total`     — total records read from the file
    - `:inserted`  — records that did not previously exist and were inserted
    - `:updated`   — records that already existed and were replaced
    - `:failed`    — records that could not be processed (e.g. a bad batch)

- Accepted `opts`:
    - `:batch_size` (integer, default 500) — how many records per
      `insert_all` call
    - `:on_conflict` (atom or keyword, default `:replace_all`) — passed
      directly to `Repo.insert_all` as the `on_conflict:` option
    - `:conflict_target` (atom or list, default `[]`) — the columns that
      identify a duplicate (e.g. `[:external_id]`). Passed as
      `conflict_target:` when non-empty and omitted entirely when `[]`.
      Ecto cannot build a `:replace_all` upsert without the conflict
      columns, so when there are records to insert, `on_conflict` is the
      default `:replace_all`, and no `:conflict_target` was given, `ingest`
      returns `{:error, :conflict_target_required}` before attempting any
      batch (file and JSON errors are still reported first, and an empty
      array still returns the zeroed stats). Any other `on_conflict` value
      (e.g. `:nothing`) needs no `:conflict_target`.
    - `:returning` (boolean, default `true`) — when `true`, use
      `returning: true` in `insert_all` so you can distinguish inserts from
      updates by inspecting the returned rows

Because `insert_all` bypasses Ecto's changeset callbacks and automatic
`timestamps()`, prepare each record before inserting it: `Jason.decode/1`
returns maps with **string** keys, so convert each record's keys to the atom
field names declared on `schema` (silently dropping any key the schema does
not define), and set both `inserted_at` and `updated_at` to the current time.
The target table declares these two timestamp columns `NOT NULL`, so records
inserted without them fail the batch.

To tell inserts from updates: when `returning: true`, compare the row's
`inserted_at` and `updated_at` timestamps. If they are equal (within 1 second),
count the row as inserted; otherwise count it as updated. A fresh insert sets
both timestamps to the same current time, so they are equal and it counts as an
insert; an upsert that preserves the original (older) `inserted_at` leaves
`updated_at` newer, so it counts as an update. If `returning` is false, add all
successfully processed rows to `:inserted` and leave `:updated` as 0.

The module must handle these error conditions gracefully — never raise:
- File not found → `{:error, :file_not_found}`
- File is not valid JSON → `{:error, :invalid_json}`
- File contains valid JSON but not a top-level array →
  `{:error, :not_a_list}`
- A batch `insert_all` call fails → log the error, add the batch size to
  `:failed`, and continue with the remaining batches (partial success is
  still `{:ok, stats}`)

Use `File.read/1` + `Jason.decode/1` for I/O and parsing. Stream or chunk
the decoded list with `Enum.chunk_every/2` — do not load multiple copies of
the list into memory simultaneously. Use `require Logger` and emit a
`Logger.info/1` line after every batch with the running totals.

Give me the complete module in a single file. Assume Jason and Ecto are
available as dependencies; do not add anything else.
