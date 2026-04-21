Write me an Elixir module called `MultiSchemaIngestion` that reads a JSON array
file where each record contains a `"type"` discriminator field, routes records
to the appropriate Ecto schema based on a caller-supplied routing map, and
batch-inserts each group into its respective database table.

I need these functions in the public API:

- `MultiSchemaIngestion.ingest(repo, routing, file_path, opts \\ [])` — the
  main entry point. `routing` is a map from type-discriminator strings to Ecto
  schema modules, e.g. `%{"order" => MyApp.Order, "refund" => MyApp.Refund}`.

  It reads the JSON file at `file_path`, decodes the top-level array, groups
  records by their `"type"` field, and for each group inserts rows in batches
  via `repo.insert_all/3`. It must return `{:ok, stats}` on success or
  `{:error, reason}` on failure.

  `stats` is a map with these keys:
    - `:total`          — total records read from the file (integer)
    - `:by_schema`      — a map from schema module to per-schema stats:
                          `%{inserted: integer(), failed: integer()}`
    - `:unroutable`     — count of records whose `"type"` value did not match
                          any key in the routing map (integer)
    - `:missing_type`   — count of records that had no `"type"` field at all
                          (integer)

- Accepted `opts`:
    - `:batch_size` (integer, default 500) — how many records per
      `insert_all` call, applied independently per schema group
    - `:on_conflict` (atom or keyword, default `:nothing`) — passed
      to `Repo.insert_all` as `on_conflict:`
    - `:conflict_target` (atom, list, or a map from schema module to
      atom/list, default `:nothing`) — when a plain atom or list, the same
      target is used for all schemas.  When a map, each schema can have
      its own conflict target, e.g.
      `%{MyApp.Order => [:order_id], MyApp.Refund => [:refund_id]}`
    - `:type_field` (string, default `"type"`) — the JSON key used as the
      type discriminator

Processing order: records for each schema group are inserted in the order
they appeared in the original file.  Groups are processed in the order of
their first appearance.

Before insertion, convert string-keyed JSON maps to atom-keyed maps using
only fields declared on each target schema (via `schema.__schema__(:fields)`),
drop the discriminator field, and inject `inserted_at` / `updated_at`
timestamps if the schema declares them.

The module must handle these error conditions gracefully — never raise:
- File not found → `{:error, :file_not_found}`
- File is not valid JSON → `{:error, :invalid_json}`
- File contains valid JSON but not a top-level array →
  `{:error, :not_a_list}`
- A record has no `"type"` field → count as `:missing_type`, skip it
- A record's `"type"` value is not in the routing map → count as
  `:unroutable`, skip it
- A batch `insert_all` call fails → log the error, add the batch size to
  that schema's `:failed` count, and continue with remaining batches

Use `File.read/1` + `Jason.decode/1` for I/O and parsing. Use
`Enum.chunk_every/2` for batching. Use `require Logger` and emit a
`Logger.info/1` line after every batch with the schema name and running
totals.

Give me the complete module in a single file. Assume Jason and Ecto are
available as dependencies; do not add anything else.