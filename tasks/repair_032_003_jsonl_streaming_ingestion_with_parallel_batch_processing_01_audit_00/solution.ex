defmodule JsonlIngestion do
  @moduledoc """
  Streams a JSONL (JSON Lines) file line by line and upserts records into a
  database table via Ecto in configurable batches, optionally in parallel.

  The pipeline is fully lazy: lines are read, parsed, prepared and chunked as
  they flow, so at most one batch of rows (plus the concurrency window, when
  `:max_concurrency` is greater than 1) is resident in memory at any time.  The
  full file is never buffered.

  Because each line is parsed independently, a single malformed line does not
  abort the import — it is simply counted as `:skipped`.  Likewise a batch whose
  `insert_all` raises is counted in `:failed` and the remaining batches continue.

  ## Example

      JsonlIngestion.ingest(MyApp.Repo, MyApp.Event, "/data/events.jsonl",
        batch_size:      2_000,
        on_conflict:     :replace_all,
        conflict_target: [:event_id],
        max_concurrency: 4,
        timeout:         60_000
      )
      #=> {:ok, %{total: 100_000, inserted: 99_950, skipped: 50, failed: 0}}
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
          skipped: integer(),
          failed: integer()
        }
  @type ingest_opts :: [
          batch_size: pos_integer(),
          on_conflict: atom() | keyword(),
          conflict_target: atom() | [atom()],
          max_concurrency: pos_integer(),
          timeout: pos_integer()
        ]

  @typep event :: :skipped | {:batch, [map()]}
  @typep result ::
           :skipped | {:ok, non_neg_integer(), non_neg_integer()} | {:error, non_neg_integer()}

  # ---------------------------------------------------------------------------
  # Defaults
  # ---------------------------------------------------------------------------

  @default_batch_size 500
  @default_on_conflict :replace_all
  @default_conflict_target :nothing
  @default_max_concurrency 1
  @default_timeout 30_000

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Ingests records from a JSONL file into the database.

  ## Parameters

    - `repo`      – An Ecto repository module.
    - `schema`    – An Ecto schema module whose table receives the rows.
    - `file_path` – Path to a UTF-8 JSONL file (one JSON object per line).
    - `opts`      – Keyword list; see module doc for accepted keys.

  ## Return values

    - `{:ok, stats}` – Always returned when the file exists, even if every
                       line was malformed or every batch failed.
    - `{:error, :file_not_found}` – The file does not exist.
  """
  @spec ingest(repo(), schema(), String.t(), ingest_opts()) ::
          {:ok, stats()} | {:error, :file_not_found}
  def ingest(repo, schema, file_path, opts \\ []) do
    if File.exists?(file_path) do
      cfg = %{
        batch_size: Keyword.get(opts, :batch_size, @default_batch_size),
        on_conflict: Keyword.get(opts, :on_conflict, @default_on_conflict),
        conflict_target: Keyword.get(opts, :conflict_target, @default_conflict_target),
        max_concurrency: Keyword.get(opts, :max_concurrency, @default_max_concurrency),
        timeout: Keyword.get(opts, :timeout, @default_timeout)
      }

      {:ok, stream_and_process(repo, schema, file_path, cfg)}
    else
      Logger.error("[JsonlIngestion] File not found: #{inspect(file_path)}")
      {:error, :file_not_found}
    end
  end

  # ---------------------------------------------------------------------------
  # Streaming pipeline
  # ---------------------------------------------------------------------------

  @spec stream_and_process(repo(), schema(), String.t(), map()) :: stats()
  defp stream_and_process(repo, schema, file_path, cfg) do
    schema_keys = schema_field_set(schema)
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    initial_acc = %{total: 0, inserted: 0, skipped: 0, failed: 0}

    stats =
      file_path
      |> event_stream(schema_keys, now, cfg.batch_size)
      |> reduce_events(repo, schema, cfg, initial_acc)

    Logger.info("[JsonlIngestion] Finished. Final stats: #{format_stats(stats)}")
    stats
  end

  # Builds a lazy stream of `:skipped` / `{:batch, rows}` events.  Only the rows
  # of the batch currently being accumulated are ever held in memory.
  @spec event_stream(String.t(), MapSet.t(String.t()), NaiveDateTime.t(), pos_integer()) ::
          Enumerable.t()
  defp event_stream(file_path, schema_keys, now, batch_size) do
    file_path
    |> File.stream!()
    |> Stream.map(&String.trim/1)
    |> Stream.reject(&(&1 == ""))
    |> Stream.transform(
      fn -> {[], 0} end,
      fn line, {buffer, count} ->
        case parse_line(line) do
          {:ok, record} ->
            buffer = [prepare_row(record, schema_keys, now) | buffer]
            count = count + 1

            if count >= batch_size do
              {[{:batch, Enum.reverse(buffer)}], {[], 0}}
            else
              {[], {buffer, count}}
            end

          :skip ->
            {[:skipped], {buffer, count}}
        end
      end,
      fn
        {[], _count} -> {[], {[], 0}}
        {buffer, _count} -> {[{:batch, Enum.reverse(buffer)}], {[], 0}}
      end,
      fn _acc -> :ok end
    )
  end

  # ---------------------------------------------------------------------------
  # Event reduction (sequential vs parallel)
  # ---------------------------------------------------------------------------

  @spec reduce_events(Enumerable.t(), repo(), schema(), map(), stats()) :: stats()
  defp reduce_events(stream, repo, schema, %{max_concurrency: mc} = cfg, acc) when mc > 1 do
    stream
    |> Task.async_stream(fn event -> handle_event(event, repo, schema, cfg) end,
      max_concurrency: mc,
      timeout: cfg.timeout,
      on_timeout: :kill_task
    )
    |> Enum.reduce(acc, fn
      {:ok, result}, inner ->
        apply_result(result, inner)

      {:exit, reason}, inner ->
        Logger.error("[JsonlIngestion] Batch task exited: #{inspect(reason)}")
        inner
    end)
  end

  defp reduce_events(stream, repo, schema, cfg, acc) do
    Enum.reduce(stream, acc, fn event, inner ->
      event
      |> handle_event(repo, schema, cfg)
      |> apply_result(inner)
    end)
  end

  @spec handle_event(event(), repo(), schema(), map()) :: result()
  defp handle_event(:skipped, _repo, _schema, _cfg), do: :skipped

  defp handle_event({:batch, rows}, repo, schema, cfg),
    do: try_insert_batch(repo, schema, rows, cfg)

  @spec apply_result(result(), stats()) :: stats()
  defp apply_result(:skipped, acc),
    do: %{acc | total: acc.total + 1, skipped: acc.skipped + 1}

  defp apply_result({:ok, count, size}, acc) do
    new_acc = %{acc | total: acc.total + size, inserted: acc.inserted + count}

    Logger.info(
      "[JsonlIngestion] Batch done — size: #{size}, inserted: #{count}. " <>
        "Running totals — #{format_stats(new_acc)}"
    )

    new_acc
  end

  defp apply_result({:error, size}, acc) do
    new_acc = %{acc | total: acc.total + size, failed: acc.failed + size}

    Logger.info(
      "[JsonlIngestion] Batch failed — size: #{size}. " <>
        "Running totals — #{format_stats(new_acc)}"
    )

    new_acc
  end

  # ---------------------------------------------------------------------------
  # Batch insertion
  # ---------------------------------------------------------------------------

  @spec try_insert_batch(repo(), schema(), [map()], map()) ::
          {:ok, non_neg_integer(), non_neg_integer()} | {:error, non_neg_integer()}
  defp try_insert_batch(repo, schema, batch, cfg) do
    batch_size = length(batch)

    insert_opts = [
      on_conflict: cfg.on_conflict,
      conflict_target: cfg.conflict_target
    ]

    try do
      {count, _} = repo.insert_all(schema, batch, insert_opts)
      {:ok, count, batch_size}
    rescue
      error ->
        Logger.error(
          "[JsonlIngestion] Batch failed (#{batch_size} records): " <>
            Exception.format(:error, error, __STACKTRACE__)
        )

        {:error, batch_size}
    catch
      kind, reason ->
        Logger.error(
          "[JsonlIngestion] Batch failed with #{kind} " <>
            "(#{batch_size} records skipped): #{inspect(reason)}"
        )

        {:error, batch_size}
    end
  end

  # ---------------------------------------------------------------------------
  # Line parsing
  # ---------------------------------------------------------------------------

  @spec parse_line(String.t()) :: {:ok, map()} | :skip
  defp parse_line(line) do
    case Jason.decode(line) do
      {:ok, value} when is_map(value) ->
        {:ok, value}

      {:ok, _non_map} ->
        Logger.warning("[JsonlIngestion] Line is valid JSON but not an object, skipping")
        :skip

      {:error, reason} ->
        Logger.warning("[JsonlIngestion] Malformed JSON line, skipping: #{inspect(reason)}")
        :skip
    end
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

  @spec prepare_row(map(), MapSet.t(String.t()), NaiveDateTime.t()) :: map()
  defp prepare_row(row, schema_keys, now) do
    base =
      row
      |> Enum.filter(fn {k, _v} -> MapSet.member?(schema_keys, k) end)
      |> Enum.map(fn {k, v} -> {String.to_existing_atom(k), v} end)
      |> Map.new()

    base
    |> maybe_put_new(:inserted_at, now, schema_keys)
    |> maybe_put_new(:updated_at, now, schema_keys)
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
  # Formatting
  # ---------------------------------------------------------------------------

  @spec format_stats(stats()) :: String.t()
  defp format_stats(%{total: t, inserted: i, skipped: s, failed: f}),
    do: "total=#{t} inserted=#{i} skipped=#{s} failed=#{f}"
end
