# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `validate_list` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

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

## The module with `validate_list` missing

```elixir
defmodule DataIngestion do
  @moduledoc """
  Reads a large JSON array file and upserts its records into a database table
  via Ecto in configurable batches.

  `Jason.decode/1` always returns string-keyed maps.  This module converts
  those keys to atoms (using only fields declared on the schema) and injects
  `inserted_at` / `updated_at` timestamps before calling `insert_all`, because
  `insert_all` bypasses Ecto callbacks and will not set timestamps on its own.

  ## Example

      DataIngestion.ingest(MyApp.Repo, MyApp.Product, "/tmp/products.json",
        batch_size:       1_000,
        on_conflict:      :replace_all,
        conflict_target:  [:external_id],
        returning:        true
      )
      #=> {:ok, %{total: 42_000, inserted: 40_100, updated: 1_900, failed: 0}}
  """

  require Logger

  # ---------------------------------------------------------------------------
  # Types
  # ---------------------------------------------------------------------------

  @type repo :: module()
  @type schema :: module()
  @type file_path :: String.t()
  @type stats :: %{total: integer(), inserted: integer(), updated: integer(), failed: integer()}
  @type ingest_opts :: [
          batch_size: pos_integer(),
          on_conflict: atom() | keyword(),
          conflict_target: atom() | [atom()],
          returning: boolean()
        ]

  # ---------------------------------------------------------------------------
  # Defaults
  # ---------------------------------------------------------------------------

  @default_batch_size 500
  @default_on_conflict :replace_all
  @default_conflict_target []
  @default_returning true

  # Tolerance window (seconds) used to tell a fresh INSERT from an UPDATE when
  # comparing the returned inserted_at / updated_at timestamps.
  @insert_window_seconds 1

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Ingests records from a JSON array file into the database.

  ## Parameters

    - `repo`      – An Ecto repository module (e.g. `MyApp.Repo`).
    - `schema`    – An Ecto schema module whose table will receive the rows.
    - `file_path` – Absolute or relative path to a UTF-8 JSON file whose
                    top-level value is an array of objects.
    - `opts`      – Keyword list; see module doc for accepted keys.

  ## Return values

    - `{:ok, stats}` – Always returned when the file was read and parsed
                       successfully, even if individual batches failed.
    - `{:error, :file_not_found}` – The file does not exist or is unreadable.
    - `{:error, :invalid_json}`   – The file contents are not valid JSON.
    - `{:error, :not_a_list}`     – The JSON root value is not an array.
    - `{:error, :conflict_target_required}` – `on_conflict` is the default
      `:replace_all` but no `:conflict_target` was given (Ecto requires the
      conflict columns to build an upsert).
  """
  @spec ingest(repo(), schema(), file_path(), ingest_opts()) ::
          {:ok, stats()}
          | {:error, :file_not_found | :invalid_json | :not_a_list | :conflict_target_required}
  def ingest(repo, schema, file_path, opts \\ []) do
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)
    on_conflict = Keyword.get(opts, :on_conflict, @default_on_conflict)
    conflict_target = Keyword.get(opts, :conflict_target, @default_conflict_target)
    returning = Keyword.get(opts, :returning, @default_returning)

    with {:ok, raw} <- read_file(file_path),
         {:ok, parsed} <- parse_json(raw),
         {:ok, records} <- validate_list(parsed),
         :ok <- validate_conflict_opts(records, on_conflict, conflict_target) do
      cfg = %{
        batch_size: batch_size,
        on_conflict: on_conflict,
        conflict_target: conflict_target,
        returning: returning
      }

      {:ok, process_batches(repo, schema, records, cfg)}
    end
  end

  # ---------------------------------------------------------------------------
  # File I/O and validation
  # ---------------------------------------------------------------------------

  @spec read_file(file_path()) :: {:ok, binary()} | {:error, :file_not_found}
  defp read_file(path) do
    case File.read(path) do
      {:ok, contents} ->
        {:ok, contents}

      {:error, reason} ->
        Logger.error("[DataIngestion] Could not read file #{inspect(path)}: #{inspect(reason)}")
        {:error, :file_not_found}
    end
  end

  @spec parse_json(binary()) :: {:ok, term()} | {:error, :invalid_json}
  defp parse_json(raw) do
    case Jason.decode(raw) do
      {:ok, value} ->
        {:ok, value}

      {:error, reason} ->
        Logger.error("[DataIngestion] JSON parse error: #{inspect(reason)}")
        {:error, :invalid_json}
    end
  end

  defp validate_list(value) when is_list(value) do
    # TODO
  end

  # ---------------------------------------------------------------------------
  # Batch processing
  # ---------------------------------------------------------------------------

  @spec process_batches(repo(), schema(), list(), map()) :: stats()
  defp process_batches(repo, schema, records, cfg) do
    total = length(records)
    schema_keys = schema_field_set(schema)
    initial_acc = %{total: total, inserted: 0, updated: 0, failed: 0}

    stats =
      records
      |> Enum.chunk_every(cfg.batch_size)
      |> Enum.reduce(initial_acc, fn raw_batch, acc ->
        # Prepare rows: atomise keys, drop unknown fields, inject timestamps.
        prepared = prepare_rows(raw_batch, schema_keys)
        process_batch(repo, schema, prepared, length(raw_batch), cfg, acc)
      end)

    Logger.info("[DataIngestion] Finished. Final stats: #{format_stats(stats)}")
    stats
  end

  @spec process_batch(repo(), schema(), list(), non_neg_integer(), map(), stats()) :: stats()
  defp process_batch(repo, schema, prepared_batch, raw_count, cfg, acc) do
    insert_opts = build_insert_opts(cfg)

    try do
      {_count, returned_rows} = repo.insert_all(schema, prepared_batch, insert_opts)
      {ins, upd} = classify_rows(returned_rows, raw_count, cfg.returning)

      new_acc = %{acc | inserted: acc.inserted + ins, updated: acc.updated + upd}

      Logger.info(
        "[DataIngestion] Batch done — " <>
          "size: #{raw_count}, inserted: #{ins}, updated: #{upd}. " <>
          "Running totals — #{format_stats(new_acc)}"
      )

      new_acc
    rescue
      error ->
        Logger.error(
          "[DataIngestion] Batch failed (#{raw_count} records skipped): " <>
            Exception.format(:error, error, __STACKTRACE__)
        )

        %{acc | failed: acc.failed + raw_count}
    catch
      kind, reason ->
        Logger.error(
          "[DataIngestion] Batch failed with #{kind} " <>
            "(#{raw_count} records skipped): #{inspect(reason)}"
        )

        %{acc | failed: acc.failed + raw_count}
    end
  end

  # ---------------------------------------------------------------------------
  # Row preparation
  # ---------------------------------------------------------------------------

  # Returns the set of field name *strings* declared on the schema, excluding
  # virtual fields.  We compare against strings (not atoms) because that is
  # what Jason gives us, avoiding the need for String.to_atom/1 on arbitrary
  # untrusted input.
  @spec schema_field_set(schema()) :: MapSet.t(String.t())
  defp schema_field_set(schema) do
    schema.__schema__(:fields)
    |> Enum.map(&Atom.to_string/1)
    |> MapSet.new()
  end

  # Converts a list of string-keyed JSON maps into the atom-keyed maps that
  # `insert_all` expects, filtering to only the columns the schema knows about
  # and injecting `inserted_at` / `updated_at` when the schema declares them.
  @spec prepare_rows(list(map()), MapSet.t(String.t())) :: list(map())
  defp prepare_rows(raw_rows, schema_keys) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    Enum.map(raw_rows, fn row ->
      base =
        row
        |> Enum.filter(fn {k, _v} -> MapSet.member?(schema_keys, k) end)
        |> Enum.map(fn {k, v} ->
          # Safe: the atom already exists because it was interned when the
          # schema module was compiled.
          {String.to_existing_atom(k), v}
        end)
        |> Map.new()

      # Only inject timestamps if the schema actually has them; avoids errors
      # on schemas that do not call `timestamps()`.
      base
      |> maybe_put_new(:inserted_at, now, schema_keys)
      |> maybe_put_new(:updated_at, now, schema_keys)
    end)
  end

  @spec maybe_put_new(map(), atom(), term(), MapSet.t(String.t())) :: map()
  defp maybe_put_new(row, field, value, schema_keys) do
    if MapSet.member?(schema_keys, Atom.to_string(field)) do
      Map.put_new(row, field, value)
    else
      row
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  # `:replace_all` cannot be built without knowing which columns identify the
  # conflict — surfaced as one caller error before any batch is attempted,
  # rather than one opaque Ecto raise per batch. File/JSON problems are
  # reported first, and an empty array has no upsert to build, so both keep
  # their own documented results.
  @spec validate_conflict_opts([map()], atom() | keyword(), atom() | [atom()]) ::
          :ok | {:error, :conflict_target_required}
  defp validate_conflict_opts([], _on_conflict, _target), do: :ok

  defp validate_conflict_opts([_ | _], :replace_all, []),
    do: {:error, :conflict_target_required}

  defp validate_conflict_opts(_records, _on_conflict, _target), do: :ok

  @spec build_insert_opts(map()) :: keyword()
  defp build_insert_opts(cfg) do
    # An empty conflict_target means "none": the option is omitted rather
    # than passed — Ecto accepts only column lists / fragments there, and
    # on_conflict values like :raise or :nothing need no target at all.
    base =
      if cfg.conflict_target == [] do
        [on_conflict: cfg.on_conflict]
      else
        [on_conflict: cfg.on_conflict, conflict_target: cfg.conflict_target]
      end

    if cfg.returning, do: Keyword.put(base, :returning, true), else: base
  end

  # Determines how many rows in a batch were inserted vs updated.
  #
  # When `returning: true`, Ecto gives back one struct / map per affected row.
  # A row is treated as a fresh insert when its `inserted_at` and `updated_at`
  # timestamps are equal within @insert_window_seconds (both were written in
  # this call).  A row whose `updated_at` trails `inserted_at` was overwriting
  # a pre-existing record whose original `inserted_at` was preserved.
  #
  # When `returning: false`, `insert_all` returns `{count, nil}`, so we cannot
  # distinguish inserts from updates — credit everything to `:inserted`.
  @spec classify_rows(list() | nil, non_neg_integer(), boolean()) ::
          {non_neg_integer(), non_neg_integer()}
  defp classify_rows(_rows, count, false), do: {count, 0}
  defp classify_rows(nil, count, _ret), do: {count, 0}

  defp classify_rows(rows, _count, true) do
    Enum.reduce(rows, {0, 0}, fn row, {ins, upd} ->
      if timestamps_equal?(get_ts(row, :inserted_at), get_ts(row, :updated_at)) do
        {ins + 1, upd}
      else
        {ins, upd + 1}
      end
    end)
  end

  # Accepts both atom-keyed structs/maps and string-keyed plain maps.
  @spec get_ts(map() | struct(), atom()) :: NaiveDateTime.t() | DateTime.t() | nil
  defp get_ts(row, field) when is_map(row) do
    Map.get(row, field) || Map.get(row, Atom.to_string(field))
  end

  @spec timestamps_equal?(term(), term()) :: boolean()
  defp timestamps_equal?(nil, _), do: false
  defp timestamps_equal?(_, nil), do: false

  defp timestamps_equal?(%NaiveDateTime{} = a, %NaiveDateTime{} = b),
    do: abs(NaiveDateTime.diff(a, b, :second)) <= @insert_window_seconds

  defp timestamps_equal?(%DateTime{} = a, %DateTime{} = b),
    do: abs(DateTime.diff(a, b, :second)) <= @insert_window_seconds

  defp timestamps_equal?(_, _), do: false

  @spec format_stats(stats()) :: String.t()
  defp format_stats(%{total: t, inserted: i, updated: u, failed: f}),
    do: "total=#{t} inserted=#{i} updated=#{u} failed=#{f}"
end
```

Give me only the complete implementation of `validate_list` (including the
`@doc`/`@spec`/`@impl` lines shown above it in the module, if any) — the
function alone, not the whole module.
