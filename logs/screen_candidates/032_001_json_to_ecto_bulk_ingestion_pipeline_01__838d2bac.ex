defmodule DataIngestion do
  @moduledoc """
  Bulk ingestion of a large JSON array file into a database table via Ecto.

  The file at the given path must contain a top-level JSON array of objects.
  The decoded list is chunked with `Enum.chunk_every/2` and each chunk is
  written with a single `Repo.insert_all/3` upsert call.

  Statistics are accumulated across batches and returned as a map:

    * `:total`    — total records read from the file
    * `:inserted` — records that did not previously exist and were inserted
    * `:updated`  — records that already existed and were replaced
    * `:failed`   — records that could not be processed (e.g. a bad batch)

  Inserts are distinguished from updates by comparing the `inserted_at` and
  `updated_at` timestamps of the rows returned by `returning: true`: rows whose
  timestamps are within one second of each other are counted as inserts, all
  other rows as updates. When `returning: false`, every successfully written row
  is counted as an insert.

  Errors never escape as exceptions — they are reported as `{:error, reason}`
  tuples, and a failing batch is logged and skipped so that the remaining
  batches still run (partial success is still `{:ok, stats}`).

  ## Examples

      DataIngestion.ingest(MyApp.Repo, MyApp.Event, "events.json",
        batch_size: 1_000,
        conflict_target: [:external_id]
      )
      #=> {:ok, %{total: 2_500, inserted: 2_400, updated: 100, failed: 0}}

  """

  require Logger

  @default_batch_size 500
  @default_on_conflict :replace_all
  @default_conflict_target []
  @default_returning true

  # Rows whose inserted_at/updated_at differ by no more than this many seconds
  # are considered freshly inserted rather than updated.
  @insert_tolerance_seconds 1

  @type stats :: %{
          total: non_neg_integer(),
          inserted: non_neg_integer(),
          updated: non_neg_integer(),
          failed: non_neg_integer()
        }

  @type reason :: :file_not_found | :invalid_json | :not_a_list | :conflict_target_required

  @type option ::
          {:batch_size, pos_integer()}
          | {:on_conflict, atom() | keyword()}
          | {:conflict_target, atom() | [atom()]}
          | {:returning, boolean()}

  @doc """
  Reads the JSON array at `file_path` and upserts it into `schema` using `repo`.

  The decoded list is split into batches of `:batch_size` records and each batch
  is written with a single `repo.insert_all/3` call.

  ## Options

    * `:batch_size` — records per `insert_all` call (default `#{@default_batch_size}`)
    * `:on_conflict` — passed straight through to `Repo.insert_all` as
      `on_conflict:` (default `:replace_all`)
    * `:conflict_target` — the columns identifying a duplicate row, e.g.
      `[:external_id]`. Passed as `conflict_target:` when non-empty and omitted
      entirely when `[]` (default `[]`)
    * `:returning` — when `true`, `returning: true` is used so inserts can be
      told apart from updates via the row timestamps (default `true`)

  Ecto cannot build a `:replace_all` upsert without knowing the conflict
  columns. When there are records to write, `:on_conflict` is the default
  `:replace_all` and no `:conflict_target` was given, this returns
  `{:error, :conflict_target_required}` before any batch is attempted. File and
  JSON errors are still reported first, and an empty array still returns the
  zeroed stats.

  ## Returns

    * `{:ok, stats}` — see `t:stats/0`. A batch that fails to write is logged,
      counted in `:failed` and skipped; the ingest continues.
    * `{:error, :file_not_found}` — `file_path` does not exist (or is unreadable)
    * `{:error, :invalid_json}` — the file is not valid JSON
    * `{:error, :not_a_list}` — the file is valid JSON but not a top-level array
    * `{:error, :conflict_target_required}` — a `:replace_all` upsert was
      requested without `:conflict_target`

  ## Examples

      iex> DataIngestion.ingest(MyApp.Repo, MyApp.Event, "missing.json")
      {:error, :file_not_found}

  """
  @spec ingest(module(), module(), Path.t(), [option()]) :: {:ok, stats()} | {:error, reason()}
  def ingest(repo, schema, file_path, opts \\ []) do
    with {:ok, records} <- read_records(file_path),
         {:ok, config} <- build_config(opts, records) do
      {:ok, run(repo, schema, records, config)}
    end
  end

  # -- reading ---------------------------------------------------------------

  @spec read_records(Path.t()) :: {:ok, list()} | {:error, reason()}
  defp read_records(file_path) do
    with {:ok, body} <- read_file(file_path),
         {:ok, decoded} <- decode_json(body) do
      case decoded do
        records when is_list(records) -> {:ok, records}
        _other -> {:error, :not_a_list}
      end
    end
  end

  @spec read_file(Path.t()) :: {:ok, binary()} | {:error, :file_not_found}
  defp read_file(file_path) do
    case File.read(file_path) do
      {:ok, body} ->
        {:ok, body}

      {:error, posix} ->
        Logger.info("DataIngestion: could not read #{inspect(file_path)}: #{inspect(posix)}")
        {:error, :file_not_found}
    end
  end

  @spec decode_json(binary()) :: {:ok, term()} | {:error, :invalid_json}
  defp decode_json(body) do
    case Jason.decode(body) do
      {:ok, decoded} ->
        {:ok, decoded}

      {:error, error} ->
        Logger.info("DataIngestion: invalid JSON: #{inspect(error)}")
        {:error, :invalid_json}
    end
  end

  # -- configuration ---------------------------------------------------------

  @spec build_config(keyword(), list()) :: {:ok, map()} | {:error, :conflict_target_required}
  defp build_config(opts, records) do
    batch_size = Keyword.get(opts, :batch_size, @default_batch_size)
    on_conflict = Keyword.get(opts, :on_conflict, @default_on_conflict)
    conflict_target = Keyword.get(opts, :conflict_target, @default_conflict_target)
    returning = Keyword.get(opts, :returning, @default_returning)

    config = %{
      batch_size: normalize_batch_size(batch_size),
      on_conflict: on_conflict,
      conflict_target: conflict_target,
      returning: returning
    }

    if conflict_target_required?(config, records) do
      {:error, :conflict_target_required}
    else
      {:ok, config}
    end
  end

  @spec normalize_batch_size(term()) :: pos_integer()
  defp normalize_batch_size(size) when is_integer(size) and size > 0, do: size
  defp normalize_batch_size(_size), do: @default_batch_size

  @spec conflict_target_required?(map(), list()) :: boolean()
  defp conflict_target_required?(%{on_conflict: :replace_all, conflict_target: target}, records) do
    records != [] and empty_conflict_target?(target)
  end

  defp conflict_target_required?(_config, _records), do: false

  @spec empty_conflict_target?(term()) :: boolean()
  defp empty_conflict_target?([]), do: true
  defp empty_conflict_target?(_target), do: false

  # -- ingestion -------------------------------------------------------------

  @spec run(module(), module(), list(), map()) :: stats()
  defp run(repo, schema, records, config) do
    insert_opts = insert_opts(config)
    total = length(records)
    initial = %{total: total, inserted: 0, updated: 0, failed: 0}

    records
    |> Enum.chunk_every(config.batch_size)
    |> Enum.reduce(initial, fn batch, stats ->
      stats
      |> merge_batch(insert_batch(repo, schema, batch, insert_opts, config))
      |> log_progress()
    end)
  end

  @spec insert_opts(map()) :: keyword()
  defp insert_opts(config) do
    opts = [on_conflict: config.on_conflict]
    opts = if config.returning, do: Keyword.put(opts, :returning, true), else: opts

    if empty_conflict_target?(config.conflict_target) do
      opts
    else
      Keyword.put(opts, :conflict_target, config.conflict_target)
    end
  end

  @spec insert_batch(module(), module(), list(), keyword(), map()) :: map()
  defp insert_batch(repo, schema, batch, insert_opts, config) do
    entries = Enum.map(batch, &to_entry/1)

    try do
      repo.insert_all(schema, entries, insert_opts)
    rescue
      error ->
        log_batch_failure(length(batch), Exception.message(error))
        :error
    catch
      kind, value ->
        log_batch_failure(length(batch), "#{inspect(kind)}: #{inspect(value)}")
        :error
    else
      result -> tally(result, length(batch), config)
    end
  end

  @spec tally(term(), non_neg_integer(), map()) :: map()
  defp tally({count, rows}, batch_size, %{returning: true}) when is_list(rows) do
    inserted = Enum.count(rows, &inserted_row?/1)
    written = if is_integer(count), do: count, else: length(rows)

    %{
      inserted: inserted,
      updated: max(length(rows) - inserted, 0),
      failed: max(batch_size - max(written, length(rows)), 0)
    }
  end

  defp tally({count, _rows}, batch_size, _config) when is_integer(count) do
    %{inserted: count, updated: 0, failed: max(batch_size - count, 0)}
  end

  defp tally(_other, batch_size, _config) do
    %{inserted: batch_size, updated: 0, failed: 0}
  end

  @spec merge_batch(stats(), map() | :error) :: stats()
  defp merge_batch(stats, :error) do
    stats
  end

  defp merge_batch(stats, %{inserted: inserted, updated: updated, failed: failed}) do
    %{
      stats
      | inserted: stats.inserted + inserted,
        updated: stats.updated + updated,
        failed: stats.failed + failed
    }
  end

  # A batch that blew up counts entirely as failed; the size is folded in by the
  # caller via `failed_batch/2` below.
  @spec failed_batch(stats(), non_neg_integer()) :: stats()
  defp failed_batch(stats, size), do: %{stats | failed: stats.failed + size}

  # -- insert vs. update detection -------------------------------------------

  @spec inserted_row?(term()) :: boolean()
  defp inserted_row?(row) do
    case {fetch_timestamp(row, :inserted_at), fetch_timestamp(row, :updated_at)} do
      {nil, _updated} -> true
      {_inserted, nil} -> true
      {inserted, updated} -> within_tolerance?(inserted, updated)
    end
  end

  @spec fetch_timestamp(term(), atom()) :: term()
  defp fetch_timestamp(row, key) when is_map(row) do
    Map.get(row, key) || Map.get(row, Atom.to_string(key))
  end

  defp fetch_timestamp(row, key) when is_list(row), do: Keyword.get(row, key)
  defp fetch_timestamp(_row, _key), do: nil

  @spec within_tolerance?(term(), term()) :: boolean()
  defp within_tolerance?(inserted, updated) do
    case diff_seconds(inserted, updated) do
      nil -> true
      diff -> abs(diff) <= @insert_tolerance_seconds
    end
  end

  @spec diff_seconds(term(), term()) :: integer() | nil
  defp diff_seconds(%DateTime{} = a, %DateTime{} = b), do: DateTime.diff(a, b, :second)

  defp diff_seconds(%NaiveDateTime{} = a, %NaiveDateTime{} = b),
    do: NaiveDateTime.diff(a, b, :second)

  defp diff_seconds(%Date{} = a, %Date{} = b), do: Date.diff(a, b) * 86_400
  defp diff_seconds(%Time{} = a, %Time{} = b), do: Time.diff(a, b, :second)
  defp diff_seconds(a, b) when is_integer(a) and is_integer(b), do: a - b
  defp diff_seconds(_a, _b), do: nil

  # -- entries ---------------------------------------------------------------

  # `insert_all/3` wants keyword lists or maps with atom keys; JSON gives us
  # string keys, so normalize here. Unknown keys are left to Ecto to reject,
  # which surfaces as a failed batch rather than a crash.
  @spec to_entry(term()) :: map()
  defp to_entry(record) when is_map(record) do
    Map.new(record, fn {key, value} -> {to_atom(key), value} end)
  end

  defp to_entry(record), do: record

  @spec to_atom(term()) :: atom()
  defp to_atom(key) when is_atom(key), do: key

  defp to_atom(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> String.to_atom(key)
  end

  defp to_atom(key), do: key

  # -- logging ---------------------------------------------------------------

  @spec log_batch_failure(non_neg_integer(), String.t()) :: :ok
  defp log_batch_failure(size, message) do
    Logger.error("DataIngestion: batch of #{size} record(s) failed: #{message}")
  end

  @spec log_progress(stats()) :: stats()
  defp log_progress(stats) do
    Logger.info(
      "DataIngestion: total=#{stats.total} inserted=#{stats.inserted} " <>
        "updated=#{stats.updated} failed=#{stats.failed}"
    )

    stats
  end
end