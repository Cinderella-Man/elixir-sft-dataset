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

  @type repo           :: module()
  @type schema         :: module()
  @type routing        :: %{String.t() => schema()}
  @type per_schema_stats :: %{inserted: integer(), failed: integer()}
  @type stats          :: %{
    total:        integer(),
    by_schema:    %{schema() => per_schema_stats()},
    unroutable:   integer(),
    missing_type: integer()
  }

  # ---------------------------------------------------------------------------
  # Defaults
  # ---------------------------------------------------------------------------

  @default_batch_size      500
  @default_on_conflict     :nothing
  @default_conflict_target :nothing
  @default_type_field      "type"

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
      batch_size:      Keyword.get(opts, :batch_size,      @default_batch_size),
      on_conflict:     Keyword.get(opts, :on_conflict,     @default_on_conflict),
      conflict_target: Keyword.get(opts, :conflict_target, @default_conflict_target),
      type_field:      Keyword.get(opts, :type_field,      @default_type_field)
    }

    with {:ok, raw}     <- read_file(file_path),
         {:ok, parsed}  <- parse_json(raw),
         {:ok, records} <- validate_list(parsed) do
      {:ok, process_records(repo, routing, records, cfg)}
    end
  end

  # ---------------------------------------------------------------------------
  # File I/O and validation
  # ---------------------------------------------------------------------------

  defp read_file(path) do
    case File.read(path) do
      {:ok, contents}  -> {:ok, contents}
      {:error, reason} ->
        Logger.error("[MultiSchemaIngestion] Could not read file #{inspect(path)}: #{inspect(reason)}")
        {:error, :file_not_found}
    end
  end

  defp parse_json(raw) do
    case Jason.decode(raw) do
      {:ok, value}     -> {:ok, value}
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
            Logger.warning("[MultiSchemaIngestion] Record missing '#{type_field}' field, skipping")
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
      total:        total,
      by_schema:    by_schema,
      unroutable:   unroutable,
      missing_type: missing_type
    }
  end

  # ---------------------------------------------------------------------------
  # Per-schema batch insertion
  # ---------------------------------------------------------------------------

  @spec insert_schema_group(repo(), schema(), [map()], map()) :: per_schema_stats()
  defp insert_schema_group(repo, schema, records, cfg) do
    schema_keys = schema_field_set(schema)
    now         = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    conflict_target = resolve_conflict_target(cfg.conflict_target, schema)

    insert_opts = [
      on_conflict:     cfg.on_conflict,
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

        Logger.info("[MultiSchemaIngestion] #{inspect(schema)} batch done — " <>
          "size: #{batch_size}, inserted: #{count}. " <>
          "Running totals — inserted=#{new_acc.inserted} failed=#{new_acc.failed}")

        new_acc
      rescue
        error ->
          Logger.error("[MultiSchemaIngestion] #{inspect(schema)} batch failed " <>
            "(#{batch_size} records skipped): " <>
            Exception.format(:error, error, __STACKTRACE__))
          %{acc | failed: acc.failed + batch_size}
      catch
        kind, reason ->
          Logger.error("[MultiSchemaIngestion] #{inspect(schema)} batch failed " <>
            "with #{kind} (#{batch_size} records skipped): #{inspect(reason)}")
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
    |> maybe_put_new(:updated_at,  now, schema_keys)
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
