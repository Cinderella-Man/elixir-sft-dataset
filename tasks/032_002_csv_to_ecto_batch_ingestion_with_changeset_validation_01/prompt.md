Write me an Elixir module called `CsvIngestion` that reads a CSV file, validates
each row through an Ecto changeset, and inserts valid rows in batches into a
database table via Ecto.

I need these functions in the public API:

- `CsvIngestion.ingest(repo, schema, file_path, opts \\ [])` — the main entry
  point. It reads the CSV file at `file_path` using `NimbleCSV`, validates each
  parsed row by building an Ecto changeset from the schema module, collects
  valid rows, splits them into batches, and calls `repo.insert_all/3` for each
  batch. It must return `{:ok, stats}` on success or `{:error, reason}` on
  failure.
  `stats` is a map with these integer keys:
    - `:total`       — total data rows read from the file (excluding header)
    - `:inserted`    — rows successfully inserted into the database
    - `:invalid`     — rows that failed changeset validation
    - `:failed`      — rows in batches where `insert_all` raised an error

  Additionally, `stats` must include:
    - `:validation_errors` — a list of `{line_number, errors}` tuples where
      `line_number` is the 1-based line number in the CSV (header is line 1,
      first data row is line 2) and `errors` is the keyword list from
      `changeset.errors`

- Accepted `opts`:
    - `:batch_size` (integer, default 500) — how many valid records per
      `insert_all` call
    - `:on_conflict` (atom or keyword, default `:nothing`) — passed
      directly to `Repo.insert_all` as the `on_conflict:` option
    - `:conflict_target` (atom or list, default `:nothing`) — passed as
      `conflict_target:`
    - `:field_mapping` (map, default `nil`) — an optional map from CSV
      header names (strings) to schema field names (atoms), e.g.
      `%{"Product ID" => :external_id, "Product Name" => :name}`.
      When `nil`, headers are converted to snake_case atoms directly.

Row validation: for each parsed CSV row, build a changeset using
`schema.changeset(struct(schema), attrs)`. If the changeset is valid, include
the row in the insertion batch (extract the changes as a plain map). If
invalid, record the line number and errors, skip the row.

Before insertion, inject `inserted_at` and `updated_at` timestamps into each
row map if those fields exist on the schema.

The module must handle these error conditions gracefully — never raise:
- File not found → `{:error, :file_not_found}`
- File is empty (0 bytes) → `{:error, :empty_file}`
- File has a header row but zero data rows → this is valid, return
  `{:ok, stats}` with all zeroes
- A batch `insert_all` call fails → log the error, add the batch size to
  `:failed`, and continue with the remaining batches

Use `File.exists?/1` and `NimbleCSV` for I/O and parsing. Use
`Enum.chunk_every/2` for batching. Use `require Logger` and emit a
`Logger.info/1` line after every batch with the running totals.

Give me the complete module in a single file. Assume NimbleCSV, Jason, and
Ecto are available as dependencies; do not add anything else.