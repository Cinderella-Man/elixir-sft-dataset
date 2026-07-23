# Design Brief: `DataIngestion` — Batched JSON-to-Ecto Upsert Pipeline

## Problem

We need to ingest a large JSON array file into a database table through Ecto. The
file holds a top-level JSON array; we must read it, process it in batches, and
upsert each batch into the table via `Ecto`, using `repo.insert_all/3` for each
batch. Deliver an Elixir module called `DataIngestion` as the complete module in
a single file.

## Constraints

- Because `insert_all` bypasses Ecto's changeset callbacks and automatic
  `timestamps()`, each record must be prepared before inserting: `Jason.decode/1`
  returns maps with **string** keys, so convert each record's keys to the atom
  field names declared on `schema` (silently dropping any key the schema does not
  define), and set both `inserted_at` and `updated_at` to the current time. The
  target table declares these two timestamp columns `NOT NULL`, so records
  inserted without them fail the batch.
- Use `File.read/1` + `Jason.decode/1` for I/O and parsing.
- Stream or chunk the decoded list with `Enum.chunk_every/2` — do not load
  multiple copies of the list into memory simultaneously.
- Use `require Logger` and emit a `Logger.info/1` line after every batch with the
  running totals.
- The module must never raise; handle every error condition gracefully.
- Assume Jason and Ecto are available as dependencies; do not add anything else.

## Required Interface

1. `DataIngestion.ingest(repo, schema, file_path, opts \\ [])` — the main entry
   point. It reads the JSON file at `file_path`, splits the decoded list into
   batches, and calls `repo.insert_all/3` for each batch. It must return
   `{:ok, stats}` on success or `{:error, reason}` on failure.

2. `stats` is a map with these integer keys:
   - `:total`     — total records read from the file
   - `:inserted`  — records that did not previously exist and were inserted
   - `:updated`   — records that already existed and were replaced
   - `:failed`    — records that could not be processed (e.g. a bad batch)

3. Accepted `opts`:
   - `:batch_size` (integer, default 500) — how many records per `insert_all`
     call
   - `:on_conflict` (atom or keyword, default `:replace_all`) — passed directly
     to `Repo.insert_all` as the `on_conflict:` option
   - `:conflict_target` (atom or list, default `[]`) — the columns that identify
     a duplicate (e.g. `[:external_id]`). Passed as `conflict_target:` when
     non-empty and omitted entirely when `[]`. Ecto cannot build a `:replace_all`
     upsert without the conflict columns, so when there are records to insert,
     `on_conflict` is the default `:replace_all`, and no `:conflict_target` was
     given, `ingest` returns `{:error, :conflict_target_required}` before
     attempting any batch (file and JSON errors are still reported first, and an
     empty array still returns the zeroed stats). Any other `on_conflict` value
     (e.g. `:nothing`) needs no `:conflict_target`.
   - `:returning` (boolean, default `true`) — when `true`, use `returning: true`
     in `insert_all` so you can distinguish inserts from updates by inspecting the
     returned rows.

4. Distinguishing inserts from updates: when `returning: true`, compare the row's
   `inserted_at` and `updated_at` timestamps. If they are equal (within 1
   second), count the row as inserted; otherwise count it as updated. A fresh
   insert sets both timestamps to the same current time, so they are equal and it
   counts as an insert; an upsert that preserves the original (older)
   `inserted_at` leaves `updated_at` newer, so it counts as an update. If
   `returning` is false, add all successfully processed rows to `:inserted` and
   leave `:updated` as 0.

5. Graceful error handling — never raise — for these conditions:
   - File not found → `{:error, :file_not_found}`
   - File is not valid JSON → `{:error, :invalid_json}`
   - File contains valid JSON but not a top-level array → `{:error, :not_a_list}`
   - A batch `insert_all` call fails → log the error, add the batch size to
     `:failed`, and continue with the remaining batches (partial success is still
     `{:ok, stats}`)

## Acceptance Criteria

- `DataIngestion.ingest/4` reads the file at `file_path`, batches the decoded
  list, and upserts each batch via `repo.insert_all/3`, returning `{:ok, stats}`
  on success or `{:error, reason}` on failure.
- `stats` reports integer `:total`, `:inserted`, `:updated`, and `:failed` counts
  matching the semantics above.
- The four `opts` (`:batch_size` default 500, `:on_conflict` default
  `:replace_all`, `:conflict_target` default `[]`, `:returning` default `true`)
  behave exactly as specified, including omitting `conflict_target:` when `[]`,
  passing it when non-empty, and returning `{:error, :conflict_target_required}`
  in the described `:replace_all`-without-conflict-columns case (after file and
  JSON errors, with an empty array still returning zeroed stats, and other
  `on_conflict` values needing no `:conflict_target`).
- Each record has its string keys converted to the schema's declared atom field
  names (dropping undefined keys) and both `inserted_at` and `updated_at` set to
  the current time before insertion.
- Insert-vs-update counting follows the 1-second timestamp-equality rule under
  `returning: true`, and folds all processed rows into `:inserted` (with
  `:updated` at 0) when `returning` is false.
- The four error conditions return their specified tuples, and a failing batch
  logs, adds the batch size to `:failed`, and continues — never raising.
- Uses `File.read/1`, `Jason.decode/1`, and `Enum.chunk_every/2` without holding
  multiple copies of the list in memory, and emits a `Logger.info/1` line with
  running totals after every batch (`require Logger`).
- Delivered as one complete module file relying only on Jason and Ecto.
