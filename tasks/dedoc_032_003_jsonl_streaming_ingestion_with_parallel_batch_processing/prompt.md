# Restore the documentation

The module below works and is fully tested — its behavior is final. What it
lost is every piece of documentation. Put it back:

- a `@moduledoc` covering purpose and usage,
- a `@doc` on each public function,
- a `@spec` on each public function (plus `@type`s where they clarify).

And keep your hands off the code itself: no renames, no refactors, no added
or removed functions, identical behavior everywhere. Return the whole
documented module in one file.

## The module

```elixir
defmodule JsonlIngestion do
  require Logger

  # ---------------------------------------------------------------------------
  # Types
  # ---------------------------------------------------------------------------

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

  defp stream_and_process(repo, schema, file_path, cfg) do
    schema_keys = schema_field_set(schema)
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)
    batch_size = cfg.batch_size

    # ONE lazy pass: lines are parsed as they are read and chunked into
    # batches that CARRY their own counters ({rows, skipped, lines}), so at
    # no point does more than a batch (plus the in-flight ones) of prepared
    # rows exist — the streaming contract the prompt and moduledoc promise.
    # Skipped lines accumulate into whichever chunk is open; the trailing
    # partial chunk is emitted at EOF even when it holds only skips, so the
    # counters always survive to the final stats.
    batch_stream =
      file_path
      |> File.stream!()
      |> Stream.map(&String.trim/1)
      |> Stream.reject(&(&1 == ""))
      |> Stream.map(fn line ->
        case parse_line(line) do
          {:ok, record} -> {:rec, prepare_row(record, schema_keys, now)}
          :skip -> :skip
        end
      end)
      |> Stream.chunk_while(
        {[], 0, 0, 0},
        fn
          {:rec, row}, {rows, nrows, skipped, lines} when nrows + 1 == batch_size ->
            {:cont, {Enum.reverse([row | rows]), skipped, lines + 1}, {[], 0, 0, 0}}

          {:rec, row}, {rows, nrows, skipped, lines} ->
            {:cont, {[row | rows], nrows + 1, skipped, lines + 1}}

          :skip, {rows, nrows, skipped, lines} ->
            {:cont, {rows, nrows, skipped + 1, lines + 1}}
        end,
        fn
          {_rows, 0, 0, 0} -> {:cont, {[], 0, 0, 0}}
          {rows, _nrows, skipped, lines} -> {:cont, {Enum.reverse(rows), skipped, lines}, nil}
        end
      )

    initial_acc = %{total: 0, inserted: 0, skipped: 0, failed: 0}

    stats =
      if cfg.max_concurrency > 1 do
        insert_parallel(repo, schema, batch_stream, cfg, initial_acc)
      else
        insert_sequential(repo, schema, batch_stream, cfg, initial_acc)
      end

    Logger.info("[JsonlIngestion] Finished. Final stats: #{format_stats(stats)}")
    stats
  end

  # ---------------------------------------------------------------------------
  # Line parsing
  # ---------------------------------------------------------------------------

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

  defp schema_field_set(schema) do
    schema.__schema__(:fields)
    |> Enum.map(&Atom.to_string/1)
    |> MapSet.new()
  end

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

  defp maybe_put_new(row, field, value, schema_keys) do
    if MapSet.member?(schema_keys, Atom.to_string(field)) do
      Map.put_new(row, field, value)
    else
      row
    end
  end

  # ---------------------------------------------------------------------------
  # Sequential batch insertion
  # ---------------------------------------------------------------------------

  defp insert_sequential(repo, schema, batch_stream, cfg, initial_acc) do
    Enum.reduce(batch_stream, initial_acc, fn {rows, skipped, lines}, acc ->
      acc = %{acc | total: acc.total + lines, skipped: acc.skipped + skipped}

      case rows do
        [] -> acc
        batch -> do_insert_batch(repo, schema, batch, cfg, acc)
      end
    end)
  end

  # ---------------------------------------------------------------------------
  # Parallel batch insertion
  # ---------------------------------------------------------------------------

  defp insert_parallel(repo, schema, batch_stream, cfg, initial_acc) do
    # `Task.async_stream` consumes the batch stream lazily with bounded
    # concurrency, so parallel mode keeps the same memory ceiling. The
    # chunk counters ride through each task; a killed (timed-out) task
    # forfeits its counters — its batch's fate is genuinely unknown.
    batch_stream
    |> Task.async_stream(
      fn
        {[], skipped, lines} -> {{:ok, 0}, skipped, lines}
        {batch, skipped, lines} -> {try_insert_batch(repo, schema, batch, cfg), skipped, lines}
      end,
      max_concurrency: cfg.max_concurrency,
      timeout: cfg.timeout,
      on_timeout: :kill_task
    )
    |> Enum.reduce(initial_acc, fn
      {:ok, {{:ok, count}, skipped, lines}}, acc ->
        new_acc = %{
          acc
          | inserted: acc.inserted + count,
            skipped: acc.skipped + skipped,
            total: acc.total + lines
        }

        Logger.info(
          "[JsonlIngestion] Batch done — inserted: #{count}. " <>
            "Running totals — #{format_stats(new_acc)}"
        )

        new_acc

      {:ok, {{:error, batch_size}, skipped, lines}}, acc ->
        %{
          acc
          | failed: acc.failed + batch_size,
            skipped: acc.skipped + skipped,
            total: acc.total + lines
        }

      {:exit, :timeout}, acc ->
        Logger.error("[JsonlIngestion] Batch timed out")
        acc
    end)
  end

  defp try_insert_batch(repo, schema, batch, cfg) do
    insert_opts = [
      on_conflict: cfg.on_conflict,
      conflict_target: cfg.conflict_target
    ]

    try do
      {count, _} = repo.insert_all(schema, batch, insert_opts)
      {:ok, count}
    rescue
      error ->
        Logger.error(
          "[JsonlIngestion] Batch failed (#{length(batch)} records): " <>
            Exception.format(:error, error, __STACKTRACE__)
        )

        {:error, length(batch)}
    catch
      kind, reason ->
        Logger.error("[JsonlIngestion] Batch failed with #{kind}: #{inspect(reason)}")
        {:error, length(batch)}
    end
  end

  # ---------------------------------------------------------------------------
  # Single batch insert (sequential mode)
  # ---------------------------------------------------------------------------

  defp do_insert_batch(repo, schema, batch, cfg, acc) do
    batch_size = length(batch)

    insert_opts = [
      on_conflict: cfg.on_conflict,
      conflict_target: cfg.conflict_target
    ]

    try do
      {count, _} = repo.insert_all(schema, batch, insert_opts)

      new_acc = %{acc | inserted: acc.inserted + count}

      Logger.info(
        "[JsonlIngestion] Batch done — " <>
          "size: #{batch_size}, inserted: #{count}. " <>
          "Running totals — #{format_stats(new_acc)}"
      )

      new_acc
    rescue
      error ->
        Logger.error(
          "[JsonlIngestion] Batch failed (#{batch_size} records skipped): " <>
            Exception.format(:error, error, __STACKTRACE__)
        )

        %{acc | failed: acc.failed + batch_size}
    catch
      kind, reason ->
        Logger.error(
          "[JsonlIngestion] Batch failed with #{kind} " <>
            "(#{batch_size} records skipped): #{inspect(reason)}"
        )

        %{acc | failed: acc.failed + batch_size}
    end
  end

  # ---------------------------------------------------------------------------
  # Formatting
  # ---------------------------------------------------------------------------

  defp format_stats(%{total: t, inserted: i, skipped: s, failed: f}),
    do: "total=#{t} inserted=#{i} skipped=#{s} failed=#{f}"
end
```
