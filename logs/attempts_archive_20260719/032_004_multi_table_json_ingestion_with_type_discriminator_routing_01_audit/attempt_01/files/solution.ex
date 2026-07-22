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
    case File.read(path) do
      {:ok, contents} ->
        {:ok, contents}

      {:error, reason} ->
        Logger.error("[Ingestion] cannot read #{inspect(path)}: #{inspect(reason)}")
        {:error, :file_not_found}
    end
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

  @spec process_records(repo(), routing(), [term()], map()) :: stats()
  defp process_records(repo, routing, records, cfg) do
    total = length(records)

    # Classify each record, preserving original order.
    {groups, unroutable, missing_type} =
      Enum.reduce(records, {%{}, 0, 0}, fn record, acc ->
        classify(record, routing, cfg.type_field, acc)
      end)

    # Process each schema group.
    by_schema =
      Enum.reduce(groups, %{}, fn {schema, schema_records}, acc ->
        Map.put(acc, schema, insert_schema_group(repo, schema, schema_records, cfg))
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

  # Non-map JSON elements (strings, numbers, lists, null) can never carry a
  # discriminator, so they are counted as `missing_type` rather than raising.
  @spec classify(term(), routing(), String.t(), {map(), integer(), integer()}) ::
          {map(), integer(), integer()}
  defp classify(record, routing, type_field, {groups, unr, miss}) when is_map(record) do
    case Map.fetch(record, type_field) do
      :error ->
        Logger.warning("[Ingestion] record missing '#{type_field}', skipping")
        {groups, unr, miss + 1}

      {:ok, type_value} ->
        route(record, routing, type_value, {groups, unr, miss})
    end
  end

  defp classify(record, _routing, type_field, {groups, unr, miss}) do
    Logger.warning(
      "[Ingestion] non-map record cannot carry '#{type_field}', skipping: " <>
        inspect(record, limit: 5)
    )

    {groups, unr, miss + 1}
  end

  # `type_value` may be any JSON term (number, map, list, ...); only values that
  # match a routing key are routable, everything else counts as unroutable.
  @spec route(map(), routing(), term(), {map(), integer(), integer()}) ::
          {map(), integer(), integer()}
  defp route(record, routing, type_value, {groups, unr, miss}) do
    case Map.fetch(routing, type_value) do
      :error ->
        Logger.warning(
          "[MultiSchemaIngestion] Unknown type #{inspect(type_value, limit: 5)}, skipping"
        )

        {groups, unr + 1, miss}

      {:ok, schema} ->
        # Prepend for O(1) appends; groups are reversed before insertion.
        {Map.update(groups, schema, [record], &[record | &1]), unr, miss}
    end
  end

  # ---------------------------------------------------------------------------
  # Per-schema batch insertion
  # ---------------------------------------------------------------------------

  @spec insert_schema_group(repo(), schema(), [map()], map()) :: per_schema_stats()
  defp insert_schema_group(repo, schema, reversed_records, cfg) do
    schema_keys = schema_field_set(schema)
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    insert_opts = build_insert_opts(cfg, schema)

    initial = %{inserted: 0, failed: 0}

    reversed_records
    |> Enum.reverse()
    |> Enum.map(&prepare_row(&1, schema_keys, cfg.type_field, now))
    |> Enum.chunk_every(cfg.batch_size)
    |> Enum.reduce(initial, fn batch, acc ->
      insert_batch(repo, schema, batch, insert_opts, acc)
    end)
  end

  @spec insert_batch(repo(), schema(), [map()], keyword(), per_schema_stats()) ::
          per_schema_stats()
  defp insert_batch(repo, schema, batch, insert_opts, acc) do
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

        failed_acc(acc, schema, batch_size)
    catch
      kind, reason ->
        Logger.error(
          "[MultiSchemaIngestion] #{inspect(schema)} batch failed " <>
            "with #{kind} (#{batch_size} records skipped): #{inspect(reason)}"
        )

        failed_acc(acc, schema, batch_size)
    end
  end

  @spec failed_acc(per_schema_stats(), schema(), non_neg_integer()) :: per_schema_stats()
  defp failed_acc(acc, schema, batch_size) do
    new_acc = %{acc | failed: acc.failed + batch_size}

    Logger.info(
      "[MultiSchemaIngestion] #{inspect(schema)} batch done — " <>
        "size: #{batch_size}, inserted: 0. " <>
        "Running totals — inserted=#{new_acc.inserted} failed=#{new_acc.failed}"
    )

    new_acc
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
      |> Enum.filter(fn {k, _v} -> is_binary(k) and MapSet.member?(schema_keys, k) end)
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

  # `:nothing` is the "no conflict target" sentinel: it is not a real column, so
  # the option is omitted entirely rather than handed to Ecto.
  @spec build_insert_opts(map(), schema()) :: keyword()
  defp build_insert_opts(cfg, schema) do
    case resolve_conflict_target(cfg.conflict_target, schema) do
      :nothing -> [on_conflict: cfg.on_conflict]
      [] -> [on_conflict: cfg.on_conflict]
      target -> [on_conflict: cfg.on_conflict, conflict_target: target]
    end
  end

  @spec resolve_conflict_target(atom() | [atom()] | map(), schema()) :: atom() | [atom()]
  defp resolve_conflict_target(target, _schema) when is_atom(target), do: target
  defp resolve_conflict_target(target, _schema) when is_list(target), do: target

  defp resolve_conflict_target(target, schema) when is_map(target) do
    Map.get(target, schema, :nothing)
  end
end
