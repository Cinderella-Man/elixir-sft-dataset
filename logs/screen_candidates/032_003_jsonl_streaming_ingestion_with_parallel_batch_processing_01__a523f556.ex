defmodule JsonlIngestion do
  @moduledoc """
  Streaming ingestion of JSONL (JSON Lines) files into an Ecto-backed database table.

  The file is read lazily with `File.stream!/1`, one line at a time, so files of any size
  can be ingested without loading them into memory. Each non-blank line is decoded with
  `Jason.decode/1`; successfully decoded JSON objects are collected into batches and written
  with `Repo.insert_all/3`, optionally in parallel via `Task.async_stream/3`.

  ## Pipeline

    1. `File.stream!/1` — lazy line stream
    2. `Stream.reject/2` — drop blank lines (after trimming)
    3. `Jason.decode/1` — parse; failures and non-object values are counted as skipped
    4. Keep the decoded maps
    5. `Stream.chunk_every/2` — group into batches of `:batch_size`
    6. Insert each batch sequentially or concurrently

  ## Options

    * `:batch_size` — records per `insert_all` call (default `500`)
    * `:on_conflict` — passed to `Repo.insert_all` (default `:replace_all`)
    * `:conflict_target` — passed to `Repo.insert_all` (default `:nothing`)
    * `:max_concurrency` — parallel batch inserts when `> 1` (default `1`)
    * `:timeout` — per-batch timeout in milliseconds (default `30_000`)

  ## Statistics

  `ingest/4` returns `{:ok, stats}` where `stats` is a map with the integer keys `:total`,
  `:inserted`, `:skipped` and `:failed`.

  The module never raises: a missing file yields `{:error, :file_not_found}`, unparsable
  lines are skipped, and failing batches are logged and counted as failed while the
  remaining batches continue.
  """

  require Logger

  @default_batch_size 500
  @default_on_conflict :replace_all
  @default_conflict_target :nothing
  @default_max_concurrency 1
  @default_timeout 30_000

  @timestamp_fields [:inserted_at, :updated_at]

  @type stats :: %{total: non_neg_integer, inserted: non_neg_integer,
                   skipped: non_neg_integer, failed: non_neg_integer}

  @type opt ::
          {:batch_size, pos_integer}
          | {:on_conflict, atom | keyword}
          | {:conflict_target, atom | list}
          | {:max_concurrency, pos_integer}
          | {:timeout, pos_integer}

  @doc """
  Streams the JSONL file at `file_path` and upserts its records into `schema`'s table.

  `repo` is an `Ecto.Repo` module and `schema` an `Ecto.Schema` module. Each line of the
  file must be a JSON object; blank lines are ignored, and lines that are neither valid
  JSON nor JSON objects are skipped and counted.

  Returns `{:ok, stats}` with the keys `:total`, `:inserted`, `:skipped` and `:failed`, or
  `{:error, :file_not_found}` when `file_path` does not exist.

  ## Examples

      iex> JsonlIngestion.ingest(MyApp.Repo, MyApp.Event, "events.jsonl")
      {:ok, %{total: 3, inserted: 3, skipped: 0, failed: 0}}

      iex> JsonlIngestion.ingest(MyApp.Repo, MyApp.Event, "missing.jsonl")
      {:error, :file_not_found}

  """
  @spec ingest(module, module, Path.t(), [opt]) :: {:ok, stats} | {:error, term}
  def ingest(repo, schema, file_path, opts \\ []) do
    if File.exists?(file_path) do
      run(repo, schema, file_path, opts)
    else
      Logger.warning("JSONL ingestion aborted: file not found at #{inspect(file_path)}")
      {:error, :file_not_found}
    end
  end

  @spec run(module, module, Path.t(), [opt]) :: {:ok, stats} | {:error, term}
  defp run(repo, schema, file_path, opts) do
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)
    max_concurrency = Keyword.get(opts, :max_concurrency, @default_max_concurrency)

    counters = :counters.new(2, [:atomics])

    batches =
      file_path
      |> File.stream!()
      |> Stream.reject(&blank?/1)
      |> Stream.map(fn line -> parse_line(line, counters) end)
      |> Stream.filter(&match?({:ok, _record}, &1))
      |> Stream.map(fn {:ok, record} -> cast_record(record, schema) end)
      |> Stream.chunk_every(batch_size)

    insert_stats =
      if max_concurrency > 1 do
        insert_concurrently(batches, repo, schema, opts, max_concurrency)
      else
        insert_sequentially(batches, repo, schema, opts)
      end

    stats = Map.merge(insert_stats, counters_to_stats(counters))
    Logger.info("JSONL ingestion finished for #{inspect(file_path)}: #{inspect(stats)}")
    {:ok, stats}
  rescue
    error ->
      Logger.error("JSONL ingestion failed: #{Exception.message(error)}")
      {:error, error}
  end

  # ── Counting ──────────────────────────────────────────────────────────────────────────

  @total_ix 1
  @skipped_ix 2

  @spec counters_to_stats(:counters.counters_ref()) :: %{total: non_neg_integer,
                                                         skipped: non_neg_integer}
  defp counters_to_stats(counters) do
    %{
      total: :counters.get(counters, @total_ix),
      skipped: :counters.get(counters, @skipped_ix)
    }
  end

  @spec blank?(String.t()) :: boolean
  defp blank?(line), do: String.trim(line) == ""

  @spec parse_line(String.t(), :counters.counters_ref()) :: {:ok, map} | :skip
  defp parse_line(line, counters) do
    :counters.add(counters, @total_ix, 1)

    case Jason.decode(String.trim(line)) do
      {:ok, record} when is_map(record) ->
        {:ok, record}

      {:ok, other} ->
        :counters.add(counters, @skipped_ix, 1)
        Logger.warning("Skipping non-object JSON value: #{inspect(other, limit: 5)}")
        :skip

      {:error, error} ->
        :counters.add(counters, @skipped_ix, 1)
        Logger.warning("Skipping malformed JSON line: #{Exception.message(error)}")
        :skip
    end
  end

  # ── Record casting ────────────────────────────────────────────────────────────────────

  @spec cast_record(map, module) :: keyword
  defp cast_record(record, schema) do
    fields = schema_fields(schema)
    now = timestamp()

    entry =
      Enum.reduce(fields, [], fn field, acc ->
        case fetch_field(record, field) do
          {:ok, value} -> [{field, value} | acc]
          :error -> acc
        end
      end)

    Enum.reduce(@timestamp_fields, entry, fn field, acc ->
      if field in fields and not Keyword.has_key?(acc, field) do
        [{field, now} | acc]
      else
        acc
      end
    end)
  end

  @spec fetch_field(map, atom) :: {:ok, term} | :error
  defp fetch_field(record, field) do
    case Map.fetch(record, Atom.to_string(field)) do
      {:ok, value} -> {:ok, value}
      :error -> Map.fetch(record, field)
    end
  end

  @spec schema_fields(module) :: [atom]
  defp schema_fields(schema) do
    if function_exported?(schema, :__schema__, 1) do
      schema.__schema__(:fields)
    else
      []
    end
  end

  @spec timestamp() :: NaiveDateTime.t()
  defp timestamp, do: NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

  # ── Insertion ─────────────────────────────────────────────────────────────────────────

  @spec insert_sequentially(Enumerable.t(), module, module, [opt]) ::
          %{inserted: non_neg_integer, failed: non_neg_integer}
  defp insert_sequentially(batches, repo, schema, opts) do
    Enum.reduce(batches, %{inserted: 0, failed: 0}, fn batch, acc ->
      acc |> merge_batch_result(insert_batch(batch, repo, schema, opts)) |> log_progress()
    end)
  end

  @spec insert_concurrently(Enumerable.t(), module, module, [opt], pos_integer) ::
          %{inserted: non_neg_integer, failed: non_neg_integer}
  defp insert_concurrently(batches, repo, schema, opts, max_concurrency) do
    timeout = Keyword.get(opts, :timeout, @default_timeout)

    batches
    |> Task.async_stream(
      fn batch -> {length(batch), insert_batch(batch, repo, schema, opts)} end,
      max_concurrency: max_concurrency,
      timeout: timeout,
      on_timeout: :kill_task,
      ordered: false
    )
    |> Enum.reduce(%{inserted: 0, failed: 0}, fn
      {:ok, {_size, result}}, acc ->
        acc |> merge_batch_result(result) |> log_progress()

      {:exit, reason}, acc ->
        Logger.error("Batch insert exited: #{inspect(reason)}")
        acc |> merge_batch_result({:error, 0}) |> log_progress()
    end)
  end

  @spec insert_batch(keyword, module, module, [opt]) ::
          {:ok, non_neg_integer} | {:error, non_neg_integer}
  defp insert_batch([], _repo, _schema, _opts), do: {:ok, 0}

  defp insert_batch(batch, repo, schema, opts) do
    on_conflict = Keyword.get(opts, :on_conflict, @default_on_conflict)
    conflict_target = Keyword.get(opts, :conflict_target, @default_conflict_target)

    {count, _returned} =
      repo.insert_all(schema, batch,
        on_conflict: on_conflict,
        conflict_target: conflict_target
      )

    {:ok, count}
  rescue
    error ->
      Logger.error("Batch insert of #{length(batch)} record(s) failed: " <>
                     Exception.message(error))

      {:error, length(batch)}
  end

  @spec merge_batch_result(%{inserted: non_neg_integer, failed: non_neg_integer},
                           {:ok, non_neg_integer} | {:error, non_neg_integer}) ::
          %{inserted: non_neg_integer, failed: non_neg_integer}
  defp merge_batch_result(acc, {:ok, count}), do: %{acc | inserted: acc.inserted + count}
  defp merge_batch_result(acc, {:error, count}), do: %{acc | failed: acc.failed + count}

  @spec log_progress(%{inserted: non_neg_integer, failed: non_neg_integer}) ::
          %{inserted: non_neg_integer, failed: non_neg_integer}
  defp log_progress(acc) do
    Logger.info("JSONL ingestion progress: inserted=#{acc.inserted} failed=#{acc.failed}")
    acc
  end
end