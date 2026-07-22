defmodule MultiSchemaIngestion do
  @moduledoc """
  Reads a JSON array file whose records carry a `"type"` discriminator, routes each record to
  an Ecto schema via a caller-supplied routing map, and batch-inserts every group into its own
  database table with `Repo.insert_all/3`.

  Records are grouped by their discriminator value. Within a group the original file order is
  preserved, and groups themselves are processed in order of first appearance in the file.

  Before insertion each string-keyed JSON map is narrowed to the fields declared on the target
  schema (`schema.__schema__(:fields)`), the discriminator key is dropped, and `inserted_at` /
  `updated_at` timestamps are injected when the schema declares them.

  Failures are never raised: missing files, malformed JSON, non-array payloads, unroutable or
  untyped records, and failing batches are all reported through the return value and stats.

  ## Example

      routing = %{"order" => MyApp.Order, "refund" => MyApp.Refund}

      {:ok, stats} =
        MultiSchemaIngestion.ingest(MyApp.Repo, routing, "events.json",
          batch_size: 1_000,
          on_conflict: :nothing,
          conflict_target: %{MyApp.Order => [:order_id], MyApp.Refund => [:refund_id]}
        )

  """

  require Logger

  @default_batch_size 500
  @default_type_field "type"
  @timestamp_fields [:inserted_at, :updated_at]

  @type routing :: %{optional(String.t()) => module()}
  @type schema_stats :: %{inserted: non_neg_integer(), failed: non_neg_integer()}
  @type stats :: %{
          total: non_neg_integer(),
          by_schema: %{optional(module()) => schema_stats()},
          unroutable: non_neg_integer(),
          missing_type: non_neg_integer()
        }
  @type error_reason :: :file_not_found | :invalid_json | :not_a_list

  @doc """
  Ingests the JSON array stored at `file_path` into the tables backing `routing`'s schemas.

  `repo` is an `Ecto.Repo` module, and `routing` maps discriminator strings to Ecto schema
  modules, e.g. `%{"order" => MyApp.Order}`.

  ## Options

    * `:batch_size` — records per `insert_all/3` call, applied per schema group (default `500`)
    * `:on_conflict` — forwarded to `Repo.insert_all/3` (default `:nothing`)
    * `:conflict_target` — an atom/list used for every schema, or a map from schema module to
      atom/list for per-schema targets (default `:nothing`)
    * `:type_field` — JSON key holding the discriminator (default `"type"`)

  Returns `{:ok, stats}` where `stats` always contains an entry in `:by_schema` for every schema
  in `routing`, including schemas that received no records. Returns `{:error, :file_not_found}`,
  `{:error, :invalid_json}` or `{:error, :not_a_list}` on input problems.
  """
  @spec ingest(module(), routing(), Path.t(), keyword()) :: {:ok, stats()} | {:error, term()}
  def ingest(repo, routing, file_path, opts \\ []) do
    with {:ok, binary} <- read_file(file_path),
         {:ok, decoded} <- decode_json(binary),
         {:ok, records} <- ensure_list(decoded) do
      {:ok, run(repo, routing, records, opts)}
    end
  end

  # -- Input handling --------------------------------------------------------------------------

  @spec read_file(Path.t()) :: {:ok, binary()} | {:error, :file_not_found}
  defp read_file(file_path) do
    case File.read(file_path) do
      {:ok, binary} ->
        {:ok, binary}

      {:error, reason} ->
        Logger.info("MultiSchemaIngestion: cannot read #{inspect(file_path)}: #{inspect(reason)}")
        {:error, :file_not_found}
    end
  end

  @spec decode_json(binary()) :: {:ok, term()} | {:error, :invalid_json}
  defp decode_json(binary) do
    case Jason.decode(binary) do
      {:ok, decoded} ->
        {:ok, decoded}

      {:error, reason} ->
        Logger.info("MultiSchemaIngestion: invalid JSON: #{inspect(reason)}")
        {:error, :invalid_json}
    end
  end

  @spec ensure_list(term()) :: {:ok, list()} | {:error, :not_a_list}
  defp ensure_list(decoded) when is_list(decoded), do: {:ok, decoded}
  defp ensure_list(_decoded), do: {:error, :not_a_list}

  # -- Orchestration ---------------------------------------------------------------------------

  @spec run(module(), routing(), list(), keyword()) :: stats()
  defp run(repo, routing, records, opts) do
    type_field = Keyword.get(opts, :type_field, @default_type_field)
    batch_size = batch_size(Keyword.get(opts, :batch_size, @default_batch_size))
    on_conflict = Keyword.get(opts, :on_conflict, :nothing)
    conflict_target = Keyword.get(opts, :conflict_target, :nothing)

    {groups, missing_type, unroutable} = classify(records, routing, type_field)

    by_schema =
      Enum.reduce(groups, initial_by_schema(routing), fn {schema, reversed}, acc ->
        rows =
          reversed
          |> Enum.reverse()
          |> Enum.map(&to_row(&1, schema, type_field))

        schema_stats =
          insert_groups(repo, schema, rows, batch_size, on_conflict,
            conflict_target: conflict_target
          )

        Map.put(acc, schema, schema_stats)
      end)

    %{
      total: length(records),
      by_schema: by_schema,
      unroutable: unroutable,
      missing_type: missing_type
    }
  end

  @spec batch_size(term()) :: pos_integer()
  defp batch_size(size) when is_integer(size) and size > 0, do: size
  defp batch_size(_size), do: @default_batch_size

  @spec initial_by_schema(routing()) :: %{optional(module()) => schema_stats()}
  defp initial_by_schema(routing) do
    routing
    |> Map.values()
    |> Enum.uniq()
    |> Map.new(fn schema -> {schema, %{inserted: 0, failed: 0}} end)
  end

  # Groups records by schema, preserving first-appearance order of groups and file order within
  # each group (records are accumulated reversed and flipped later).
  @spec classify(list(), routing(), String.t()) ::
          {[{module(), [map()]}], non_neg_integer(), non_neg_integer()}
  defp classify(records, routing, type_field) do
    {acc, missing_type, unroutable} =
      Enum.reduce(records, {[], 0, 0}, fn record, {acc, missing, unrouted} ->
        case route(record, routing, type_field) do
          {:ok, schema} -> {push(acc, schema, record), missing, unrouted}
          :missing_type -> {acc, missing + 1, unrouted}
          :unroutable -> {acc, missing, unrouted + 1}
        end
      end)

    {Enum.reverse(acc), missing_type, unroutable}
  end

  @spec route(term(), routing(), String.t()) :: {:ok, module()} | :missing_type | :unroutable
  defp route(record, routing, type_field) when is_map(record) do
    case Map.fetch(record, type_field) do
      {:ok, type} ->
        case Map.fetch(routing, type) do
          {:ok, schema} -> {:ok, schema}
          :error -> :unroutable
        end

      :error ->
        :missing_type
    end
  end

  defp route(_record, _routing, _type_field), do: :missing_type

  @spec push([{module(), [map()]}], module(), map()) :: [{module(), [map()]}]
  defp push(acc, schema, record) do
    case List.keyfind(acc, schema, 0) do
      {^schema, existing} -> List.keyreplace(acc, schema, 0, {schema, [record | existing]})
      nil -> [{schema, [record]} | acc]
    end
  end

  # -- Row building ----------------------------------------------------------------------------

  @spec to_row(map(), module(), String.t()) :: keyword()
  defp to_row(record, schema, type_field) do
    fields = schema.__schema__(:fields)
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    record
    |> Map.delete(type_field)
    |> Enum.reduce([], fn {key, value}, acc ->
      case cast_field(key, fields) do
        {:ok, field} -> [{field, value} | acc]
        :error -> acc
      end
    end)
    |> Enum.reverse()
    |> put_timestamps(fields, now)
  end

  # Only converts keys that already exist as atoms and are declared on the schema, so untrusted
  # JSON can never exhaust the atom table.
  @spec cast_field(term(), [atom()]) :: {:ok, atom()} | :error
  defp cast_field(key, fields) when is_binary(key) do
    field = String.to_existing_atom(key)
    if field in fields, do: {:ok, field}, else: :error
  rescue
    ArgumentError -> :error
  end

  defp cast_field(key, fields) when is_atom(key) do
    if key in fields, do: {:ok, key}, else: :error
  end

  defp cast_field(_key, _fields), do: :error

  @spec put_timestamps(keyword(), [atom()], NaiveDateTime.t()) :: keyword()
  defp put_timestamps(row, fields, now) do
    Enum.reduce(@timestamp_fields, row, fn field, acc ->
      if field in fields and not Keyword.has_key?(acc, field) do
        Keyword.put(acc, field, now)
      else
        acc
      end
    end)
  end

  # -- Insertion -------------------------------------------------------------------------------

  @spec insert_groups(module(), module(), [keyword()], pos_integer(), term(), keyword()) ::
          schema_stats()
  defp insert_groups(repo, schema, rows, batch_size, on_conflict, opts) do
    conflict_target = conflict_target_for(Keyword.fetch!(opts, :conflict_target), schema)
    insert_opts = [on_conflict: on_conflict, conflict_target: conflict_target]

    rows
    |> Enum.chunk_every(batch_size)
    |> Enum.reduce(%{inserted: 0, failed: 0}, fn batch, acc ->
      acc
      |> merge_batch_result(insert_batch(repo, schema, batch, insert_opts))
      |> tap(&log_batch(schema, &1))
    end)
  end

  @spec insert_batch(module(), module(), [keyword()], keyword()) ::
          {:ok, non_neg_integer()} | {:error, non_neg_integer()}
  defp insert_batch(repo, schema, batch, insert_opts) do
    case repo.insert_all(schema, batch, insert_opts) do
      {count, _returning} when is_integer(count) -> {:ok, count}
      other -> raise ArgumentError, "unexpected insert_all/3 result: #{inspect(other)}"
    end
  rescue
    error ->
      Logger.error(
        "MultiSchemaIngestion: batch of #{length(batch)} failed for " <>
          "#{inspect(schema)}: #{Exception.message(error)}"
      )

      {:error, length(batch)}
  catch
    kind, reason ->
      Logger.error(
        "MultiSchemaIngestion: batch of #{length(batch)} failed for " <>
          "#{inspect(schema)}: #{inspect({kind, reason})}"
      )

      {:error, length(batch)}
  end

  @spec merge_batch_result(schema_stats(), {:ok | :error, non_neg_integer()}) :: schema_stats()
  defp merge_batch_result(acc, {:ok, count}), do: %{acc | inserted: acc.inserted + count}
  defp merge_batch_result(acc, {:error, count}), do: %{acc | failed: acc.failed + count}

  @spec log_batch(module(), schema_stats()) :: :ok
  defp log_batch(schema, %{inserted: inserted, failed: failed}) do
    Logger.info(
      "MultiSchemaIngestion: #{inspect(schema)} batch done — " <>
        "inserted=#{inserted} failed=#{failed}"
    )
  end

  @spec conflict_target_for(term(), module()) :: term()
  defp conflict_target_for(target, schema) when is_map(target) do
    Map.get(target, schema, :nothing)
  end

  defp conflict_target_for(target, _schema), do: target
end