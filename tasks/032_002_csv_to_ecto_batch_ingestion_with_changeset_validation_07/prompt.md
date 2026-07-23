# Implement the missing function

Below you'll find a task's full specification, then a working, tested
solution with one gap: `parse_csv` — every clause body swapped for
`# TODO`. Rebuild exactly that function so the module passes the task's
whole suite again, and leave every other line precisely as shown.

## The task

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
      `changeset.errors`. When every row is valid, this list is empty (`[]`).

- Accepted `opts`:
    - `:batch_size` (integer, default 500) — how many valid records per
      `insert_all` call
    - `:on_conflict` (atom or keyword, default `:nothing`) — passed
      directly to `Repo.insert_all` as the `on_conflict:` option
    - `:conflict_target` (atom or list, default `[]`) — passed as
      `conflict_target:` when non-empty and omitted entirely when `[]`
      (Ecto rejects an empty target as an unknown column, so a default-opts
      ingest must still insert). Exception: when `:on_conflict` is `:raise`,
      do NOT pass `conflict_target:` at all — Ecto forbids that combination
      and would raise on every batch. In that case pass only `on_conflict: :raise` and
      let conflicting rows surface as a normal insert error (caught and counted
      against that batch's `:failed`).
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

## The module with `parse_csv` missing

```elixir
defmodule CsvIngestion do
  @moduledoc """
  Reads a CSV file, validates each row via an Ecto changeset, and batch-inserts
  valid rows into the database.

  Invalid rows are collected with their line numbers and changeset errors so the
  caller can report validation failures without aborting the entire import.

  ## Example

      CsvIngestion.ingest(MyApp.Repo, MyApp.Product, "/tmp/products.csv",
        batch_size:     1_000,
        on_conflict:    :nothing,
        conflict_target: [:external_id],
        field_mapping:  %{"Product ID" => :external_id, "Product Name" => :name}
      )
      #=> {:ok, %{total: 5000, inserted: 4980, invalid: 18, failed: 0,
      #=>         validation_errors: [{3, [name: {"can't be blank", ...}]}, ...]}}
  """

  require Logger

  # ---------------------------------------------------------------------------
  # Types
  # ---------------------------------------------------------------------------

  @type repo :: module()
  @type schema :: module()
  @type stats :: %{
          total: integer(),
          inserted: integer(),
          invalid: integer(),
          failed: integer(),
          validation_errors: [{pos_integer(), keyword()}]
        }
  @type ingest_opts :: [
          batch_size: pos_integer(),
          on_conflict: atom() | keyword(),
          conflict_target: atom() | [atom()],
          field_mapping: map() | nil
        ]

  # ---------------------------------------------------------------------------
  # Defaults
  # ---------------------------------------------------------------------------

  @default_batch_size 500
  @default_on_conflict :nothing
  @default_conflict_target []

  # ---------------------------------------------------------------------------
  # CSV parser definition
  # ---------------------------------------------------------------------------

  NimbleCSV.define(CsvIngestion.Parser, separator: ",", escape: "\"")

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Ingests records from a CSV file into the database.

  ## Parameters

    - `repo`      – An Ecto repository module (e.g. `MyApp.Repo`).
    - `schema`    – An Ecto schema module that also exposes `changeset/2`.
    - `file_path` – Path to a UTF-8 CSV file with a header row.
    - `opts`      – Keyword list; see module doc for accepted keys.

  ## Return values

    - `{:ok, stats}` – Returned when the file was read and parsed successfully,
                       even if some rows were invalid or some batches failed.
    - `{:error, :file_not_found}` – The file does not exist.
    - `{:error, :empty_file}`     – The file is 0 bytes.
  """
  @spec ingest(repo(), schema(), String.t(), ingest_opts()) ::
          {:ok, stats()} | {:error, :file_not_found | :empty_file}
  def ingest(repo, schema, file_path, opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)
    on_conflict = Keyword.get(opts, :on_conflict, @default_on_conflict)
    conflict_target = Keyword.get(opts, :conflict_target, @default_conflict_target)
    field_mapping = Keyword.get(opts, :field_mapping, nil)

    with :ok <- check_file(file_path),
         {:ok, rows} <- parse_csv(file_path) do
      cfg = %{
        batch_size: batch_size,
        on_conflict: on_conflict,
        conflict_target: conflict_target
      }

      {:ok, process_rows(repo, schema, rows, field_mapping, cfg)}
    end
  end

  # ---------------------------------------------------------------------------
  # File checks
  # ---------------------------------------------------------------------------

  @spec check_file(String.t()) :: :ok | {:error, :file_not_found | :empty_file}
  defp check_file(path) do
    cond do
      not File.exists?(path) ->
        Logger.error("[CsvIngestion] File not found: #{inspect(path)}")
        {:error, :file_not_found}

      File.stat!(path).size == 0 ->
        Logger.error("[CsvIngestion] File is empty: #{inspect(path)}")
        {:error, :empty_file}

      true ->
        :ok
    end
  end

  # ---------------------------------------------------------------------------
  # CSV parsing
  # ---------------------------------------------------------------------------

  defp parse_csv(path) do
    # TODO
  end

  # ---------------------------------------------------------------------------
  # Row processing
  # ---------------------------------------------------------------------------

  @spec process_rows(repo(), schema(), {[String.t()], [[String.t()]]}, map() | nil, map()) ::
          stats()
  defp process_rows(repo, schema, {headers, data_rows}, field_mapping, cfg) do
    atom_headers = map_headers(headers, field_mapping)
    schema_keys = schema_field_set(schema)
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    total = length(data_rows)

    # Validate each row via changeset; split into valid and invalid.
    {valid_rows, validation_errors} =
      data_rows
      # line 2 is the first data row
      |> Enum.with_index(2)
      |> Enum.reduce({[], []}, fn {cells, line_num}, {valid_acc, err_acc} ->
        attrs = build_attrs(cells, atom_headers, schema_keys)
        changeset = schema.changeset(struct(schema), attrs)

        if changeset.valid? do
          row =
            changeset.changes
            |> maybe_put_ts(:inserted_at, now, schema_keys)
            |> maybe_put_ts(:updated_at, now, schema_keys)

          {[row | valid_acc], err_acc}
        else
          {valid_acc, [{line_num, changeset.errors} | err_acc]}
        end
      end)

    valid_rows = Enum.reverse(valid_rows)
    validation_errors = Enum.reverse(validation_errors)
    invalid_count = length(validation_errors)

    # Batch-insert valid rows.
    initial_acc = %{
      total: total,
      inserted: 0,
      invalid: invalid_count,
      failed: 0,
      validation_errors: validation_errors
    }

    stats =
      valid_rows
      |> Enum.chunk_every(cfg.batch_size)
      |> Enum.reduce(initial_acc, fn batch, acc ->
        process_batch(repo, schema, batch, cfg, acc)
      end)

    Logger.info("[CsvIngestion] Finished. Final stats: #{format_stats(stats)}")
    stats
  end

  # ---------------------------------------------------------------------------
  # Header mapping
  # ---------------------------------------------------------------------------

  @spec map_headers([String.t()], map() | nil) :: [atom()]
  defp map_headers(headers, nil) do
    Enum.map(headers, fn h ->
      h
      |> String.trim()
      |> String.downcase()
      |> String.replace(~r/\s+/, "_")
      |> String.to_atom()
    end)
  end

  defp map_headers(headers, mapping) when is_map(mapping) do
    Enum.map(headers, fn h ->
      trimmed = String.trim(h)
      Map.get(mapping, trimmed, default_atom(trimmed))
    end)
  end

  defp default_atom(header) do
    header
    |> String.downcase()
    |> String.replace(~r/\s+/, "_")
    |> String.to_atom()
  end

  # ---------------------------------------------------------------------------
  # Attribute building
  # ---------------------------------------------------------------------------

  @spec build_attrs([String.t()], [atom()], MapSet.t()) :: map()
  defp build_attrs(cells, atom_headers, schema_keys) do
    atom_headers
    |> Enum.zip(cells)
    |> Enum.filter(fn {k, _v} -> MapSet.member?(schema_keys, Atom.to_string(k)) end)
    |> Enum.map(fn {k, v} -> {k, normalize_value(v)} end)
    |> Map.new()
  end

  defp normalize_value(""), do: nil
  defp normalize_value(v), do: String.trim(v)

  # ---------------------------------------------------------------------------
  # Schema introspection
  # ---------------------------------------------------------------------------

  @spec schema_field_set(module()) :: MapSet.t(String.t())
  defp schema_field_set(schema) do
    schema.__schema__(:fields)
    |> Enum.map(&Atom.to_string/1)
    |> MapSet.new()
  end

  # ---------------------------------------------------------------------------
  # Timestamp injection
  # ---------------------------------------------------------------------------

  @spec maybe_put_ts(map(), atom(), NaiveDateTime.t(), MapSet.t()) :: map()
  defp maybe_put_ts(row, field, value, schema_keys) do
    if MapSet.member?(schema_keys, Atom.to_string(field)) do
      Map.put_new(row, field, value)
    else
      row
    end
  end

  # ---------------------------------------------------------------------------
  # Batch processing
  # ---------------------------------------------------------------------------

  @spec process_batch(repo(), schema(), [map()], map(), stats()) :: stats()
  defp process_batch(repo, schema, batch, cfg, acc) do
    # Ecto forbids `:conflict_target` together with `on_conflict: :raise` (the
    # default), so only attach a conflict target for the conflict-handling modes.
    # With `:raise`, a duplicate key surfaces as a normal constraint error (caught
    # below and counted against this batch).
    insert_opts =
      case {cfg.on_conflict, cfg.conflict_target} do
        {:raise, _} ->
          [on_conflict: :raise]

        # An empty conflict target cannot be handed to Ecto (it rejects the
        # wrapped [:nothing]/[] as an unknown column) — omit the option, so
        # a default-opts ingest actually inserts instead of failing every
        # batch inside the rescue.
        {other, []} ->
          [on_conflict: other]

        {other, target} ->
          [on_conflict: other, conflict_target: target]
      end

    batch_size = length(batch)

    try do
      {count, _} = repo.insert_all(schema, batch, insert_opts)

      new_acc = %{acc | inserted: acc.inserted + count}

      Logger.info(
        "[CsvIngestion] Batch done — " <>
          "size: #{batch_size}, inserted: #{count}. " <>
          "Running totals — #{format_stats(new_acc)}"
      )

      new_acc
    rescue
      error ->
        Logger.error(
          "[CsvIngestion] Batch failed (#{batch_size} records skipped): " <>
            Exception.format(:error, error, __STACKTRACE__)
        )

        %{acc | failed: acc.failed + batch_size}
    catch
      kind, reason ->
        Logger.error(
          "[CsvIngestion] Batch failed with #{kind} " <>
            "(#{batch_size} records skipped): #{inspect(reason)}"
        )

        %{acc | failed: acc.failed + batch_size}
    end
  end

  # ---------------------------------------------------------------------------
  # Formatting
  # ---------------------------------------------------------------------------

  @spec format_stats(stats()) :: String.t()
  defp format_stats(%{total: t, inserted: i, invalid: inv, failed: f}) do
    "total=#{t} inserted=#{i} invalid=#{inv} failed=#{f}"
  end
end
```

Reply with `parse_csv` alone (bring along any `@doc`/`@spec`/`@impl` lines
that belong directly above it) — just the function, never the whole
module.
