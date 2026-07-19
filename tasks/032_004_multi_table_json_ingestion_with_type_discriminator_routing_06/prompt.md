# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `read_file` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

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

## Additional interface contract

- `:by_schema` contains an entry for EVERY schema module in the routing map,
  including schemas that received no records — those map to
  `%{inserted: 0, failed: 0}` (so even an empty input array yields all
  schemas with zero counts).

## The module with `read_file` missing

```elixir
defmodule MultiSchemaIngestion do
  @moduledoc """
  Reads a JSON array file where each record carries a type discriminator,
  routes records to different Ecto schemas based on a caller-supplied routing
  map, and batch-inserts each group into its respective database table.

  This is useful when a single data feed contains heterogeneous record types
  that belong in different tables (e.g. orders, refunds, adjustments).

  ## Example

      routing = %{
        "order"  => MyApp.Order,
        "refund" => MyApp.Refund
      }

      MultiSchemaIngestion.ingest(MyApp.Repo, routing, "/data/feed.json",
        batch_size:      1_000,
        on_conflict:     :nothing,
        conflict_target: %{MyApp.Order => [:order_id], MyApp.Refund => [:refund_id]},
        type_field:      "record_type"
      )
      #=> {:ok, %{
      #=>   total: 10_000,
      #=>   by_schema: %{
      #=>     MyApp.Order  => %{inserted: 7_500, failed: 0},
      #=>     MyApp.Refund => %{inserted: 2_400, failed: 0}
      #=>   },
      #=>   unroutable: 80,
      #=>   missing_type: 20
      #=> }}
  """

  require Logger

  # ---------------------------------------------------------------------------
  # Types
  # ---------------------------------------------------------------------------

  @type repo :: module()
  @type schema :: module()
  @type routing :: %{String.t() => schema()}
  @type per_schema_stats :: %{inserted: integer(), failed: integer()}
  @type stats :: %{
          total: integer(),
          by_schema: %{schema() => per_schema_stats()},
          unroutable: integer(),
          missing_type: integer()
        }

  # ---------------------------------------------------------------------------
  # Defaults
  # ---------------------------------------------------------------------------

  @default_batch_size 500
  @default_on_conflict :nothing
  @default_conflict_target :nothing
  @default_type_field "type"

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Ingests records from a JSON array file, routing each record to the
  appropriate Ecto schema based on its type discriminator field.

  See module doc for accepted options.
  """
  @spec ingest(repo(), routing(), String.t(), keyword()) ::
          {:ok, stats()} | {:error, :file_not_found | :invalid_json | :not_a_list}
  def ingest(repo, routing, file_path, opts \\ []) do
    cfg = %{
      batch_size: Keyword.get(opts, :batch_size, @default_batch_size),
      on_conflict: Keyword.get(opts, :on_conflict, @default_on_conflict),
      conflict_target: Keyword.get(opts, :conflict_target, @default_conflict_target),
      type_field: Keyword.get(opts, :type_field, @default_type_field)
    }

    with {:ok, raw} <- read_file(file_path),
         {:ok, parsed} <- parse_json(raw),
         {:ok, records} <- validate_list(parsed) do
      {:ok, process_records(repo, routing, records, cfg)}
    end
  end

  # ---------------------------------------------------------------------------
  # File I/O and validation
  # ---------------------------------------------------------------------------

  defp read_file(path) do
    # TODO
  end

  defp parse_json(raw) do
    case Jason.decode(raw) do
      {:ok, value} ->
        {:ok, value}

      {:error, reason} ->
        Logger.error("[MultiSchemaIngestion] JSON parse error: #{inspect(reason)}")
        {:error, :invalid_json}
    end
  end

  defp validate_list(value) when is_list(value), do: {:ok, value}

  defp validate_list(value) do
    Logger.error("[MultiSchemaIngestion] Expected a JSON array, got: #{inspect(value, limit: 5)}")
    {:error, :not_a_list}
  end

  # ---------------------------------------------------------------------------
  # Record classification and grouping
  # ---------------------------------------------------------------------------

  @spec process_records(repo(), routing(), [map()], map()) :: stats()
  defp process_records(repo, routing, records, cfg) do
    total = length(records)
    type_field = cfg.type_field

    # Classify each record, preserving original order.
    {groups, unroutable, missing_type} =
      Enum.reduce(records, {%{}, 0, 0}, fn record, {groups, unr, miss} ->
        case Map.fetch(record, type_field) do
          :error ->
            Logger.warning("[Ingestion] record missing '#{type_field}', skipping")
            {groups, unr, miss + 1}

          {:ok, type_value} ->
            case Map.fetch(routing, type_value) do
              :error ->
                Logger.warning("[MultiSchemaIngestion] Unknown type '#{type_value}', skipping")
                {groups, unr + 1, miss}

              {:ok, schema} ->
                # Append to the group, maintaining insertion order.
                updated = Map.update(groups, schema, [record], &(&1 ++ [record]))
                {updated, unr, miss}
            end
        end
      end)

    # Process each schema group.
    by_schema =
      groups
      |> Enum.reduce(%{}, fn {schema, schema_records}, acc ->
        schema_stats = insert_schema_group(repo, schema, schema_records, cfg)
        Map.put(acc, schema, schema_stats)
      end)

    # Include schemas from routing that had zero records.
    by_schema =
      routing
      |> Map.values()
      |> Enum.uniq()
      |> Enum.reduce(by_schema, fn schema, acc ->
        Map.put_new(acc, schema, %{inserted: 0, failed: 0})
      end)

    %{
      total: total,
      by_schema: by_schema,
      unroutable: unroutable,
      missing_type: missing_type
    }
  end

  # ---------------------------------------------------------------------------
  # Per-schema batch insertion
  # ---------------------------------------------------------------------------

  @spec insert_schema_group(repo(), schema(), [map()], map()) :: per_schema_stats()
  defp insert_schema_group(repo, schema, records, cfg) do
    schema_keys = schema_field_set(schema)
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    conflict_target = resolve_conflict_target(cfg.conflict_target, schema)

    insert_opts = [
      on_conflict: cfg.on_conflict,
      conflict_target: conflict_target
    ]

    initial = %{inserted: 0, failed: 0}

    records
    |> Enum.map(&prepare_row(&1, schema_keys, cfg.type_field, now))
    |> Enum.chunk_every(cfg.batch_size)
    |> Enum.reduce(initial, fn batch, acc ->
      batch_size = length(batch)

      try do
        {count, _} = repo.insert_all(schema, batch, insert_opts)

        new_acc = %{acc | inserted: acc.inserted + count}

        Logger.info(
          "[MultiSchemaIngestion] #{inspect(schema)} batch done — " <>
            "size: #{batch_size}, inserted: #{count}. " <>
            "Running totals — inserted=#{new_acc.inserted} failed=#{new_acc.failed}"
        )

        new_acc
      rescue
        error ->
          Logger.error(
            "[MultiSchemaIngestion] #{inspect(schema)} batch failed " <>
              "(#{batch_size} records skipped): " <>
              Exception.format(:error, error, __STACKTRACE__)
          )

          %{acc | failed: acc.failed + batch_size}
      catch
        kind, reason ->
          Logger.error(
            "[MultiSchemaIngestion] #{inspect(schema)} batch failed " <>
              "with #{kind} (#{batch_size} records skipped): #{inspect(reason)}"
          )

          %{acc | failed: acc.failed + batch_size}
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Row preparation
  # ---------------------------------------------------------------------------

  @spec schema_field_set(schema()) :: MapSet.t(String.t())
  defp schema_field_set(schema) do
    schema.__schema__(:fields)
    |> Enum.map(&Atom.to_string/1)
    |> MapSet.new()
  end

  @spec prepare_row(map(), MapSet.t(String.t()), String.t(), NaiveDateTime.t()) :: map()
  defp prepare_row(row, schema_keys, type_field, now) do
    base =
      row
      |> Map.delete(type_field)
      |> Enum.filter(fn {k, _v} -> MapSet.member?(schema_keys, k) end)
      |> Enum.map(fn {k, v} -> {String.to_existing_atom(k), v} end)
      |> Map.new()

    base
    |> maybe_put_new(:inserted_at, now, schema_keys)
    |> maybe_put_new(:updated_at, now, schema_keys)
  end

  defp maybe_put_new(row, field, value, schema_keys) do
    if MapSet.member?(schema_keys, Atom.to_string(field)) do
      Map.put_new(row, field, value)
    else
      row
    end
  end

  # ---------------------------------------------------------------------------
  # Conflict target resolution
  # ---------------------------------------------------------------------------

  @spec resolve_conflict_target(atom() | [atom()] | map(), schema()) :: atom() | [atom()]
  defp resolve_conflict_target(target, _schema) when is_atom(target), do: target
  defp resolve_conflict_target(target, _schema) when is_list(target), do: target

  defp resolve_conflict_target(target, schema) when is_map(target) do
    Map.get(target, schema, :nothing)
  end
end
```

Give me only the complete implementation of `read_file` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
