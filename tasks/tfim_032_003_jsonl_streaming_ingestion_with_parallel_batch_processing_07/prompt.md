# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule JsonlIngestion do
  @moduledoc """
  Streams a JSONL (JSON Lines) file line by line and upserts records into a
  database table via Ecto in configurable batches, optionally in parallel.

  Unlike a JSON-array ingestion approach, this module never loads the full file
  into memory.  Each line is independently parsed, so a single malformed line
  does not abort the import — it is simply counted as `:skipped`.

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

    # Phase 1: Stream, parse, classify each line.
    {parsed_records, skipped_count, total_count} =
      file_path
      |> File.stream!()
      |> Stream.map(&String.trim/1)
      |> Stream.reject(&(&1 == ""))
      |> Enum.reduce({[], 0, 0}, fn line, {records, skipped, total} ->
        case parse_line(line) do
          {:ok, record} ->
            prepared = prepare_row(record, schema_keys, now)
            {[prepared | records], skipped, total + 1}

          :skip ->
            {records, skipped + 1, total + 1}
        end
      end)

    parsed_records = Enum.reverse(parsed_records)

    # Phase 2: Chunk into batches and insert.
    batches = Enum.chunk_every(parsed_records, cfg.batch_size)

    initial_acc = %{total: total_count, inserted: 0, skipped: skipped_count, failed: 0}

    stats =
      if cfg.max_concurrency > 1 do
        insert_parallel(repo, schema, batches, cfg, initial_acc)
      else
        insert_sequential(repo, schema, batches, cfg, initial_acc)
      end

    Logger.info("[JsonlIngestion] Finished. Final stats: #{format_stats(stats)}")
    stats
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
  # Sequential batch insertion
  # ---------------------------------------------------------------------------

  @spec insert_sequential(repo(), schema(), [[map()]], map(), stats()) :: stats()
  defp insert_sequential(repo, schema, batches, cfg, initial_acc) do
    Enum.reduce(batches, initial_acc, fn batch, acc ->
      do_insert_batch(repo, schema, batch, cfg, acc)
    end)
  end

  # ---------------------------------------------------------------------------
  # Parallel batch insertion
  # ---------------------------------------------------------------------------

  @spec insert_parallel(repo(), schema(), [[map()]], map(), stats()) :: stats()
  defp insert_parallel(repo, schema, batches, cfg, initial_acc) do
    results =
      batches
      |> Task.async_stream(
        fn batch -> try_insert_batch(repo, schema, batch, cfg) end,
        max_concurrency: cfg.max_concurrency,
        timeout: cfg.timeout,
        on_timeout: :kill_task
      )
      |> Enum.to_list()

    Enum.reduce(results, initial_acc, fn
      {:ok, {:ok, count}}, acc ->
        new_acc = %{acc | inserted: acc.inserted + count}

        Logger.info(
          "[JsonlIngestion] Batch done — inserted: #{count}. " <>
            "Running totals — #{format_stats(new_acc)}"
        )

        new_acc

      {:ok, {:error, batch_size}}, acc ->
        %{acc | failed: acc.failed + batch_size}

      {:exit, :timeout}, acc ->
        Logger.error("[JsonlIngestion] Batch timed out")
        acc
    end)
  end

  @spec try_insert_batch(repo(), schema(), [map()], map()) ::
          {:ok, non_neg_integer()} | {:error, non_neg_integer()}
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

  @spec do_insert_batch(repo(), schema(), [map()], map(), stats()) :: stats()
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

  @spec format_stats(stats()) :: String.t()
  defp format_stats(%{total: t, inserted: i, skipped: s, failed: f}),
    do: "total=#{t} inserted=#{i} skipped=#{s} failed=#{f}"
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule JsonlIngestionTest do
  use ExUnit.Case, async: false

  # ---------------------------------------------------------------------------
  # Minimal in-memory Ecto setup
  # ---------------------------------------------------------------------------

  defmodule TestRepo do
    use Ecto.Repo, otp_app: :jsonl_ingestion, adapter: Ecto.Adapters.SQLite3
  end

  defmodule Event do
    use Ecto.Schema

    @primary_key {:id, :id, autogenerate: true}

    schema "events" do
      field(:event_id, :string)
      field(:name, :string)
      field(:severity, :integer)
      timestamps()
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp write_jsonl!(path, lines) do
    content = Enum.join(lines, "\n")
    File.write!(path, content)
  end

  defp to_jsonl(records) do
    Enum.map(records, &Jason.encode!/1)
  end

  defp tmp_path(name),
    do:
      Path.join(
        System.tmp_dir!(),
        "#{System.pid()}_#{System.unique_integer([:positive])}_#{name}"
      )

  defp all_events, do: TestRepo.all(Event)

  # ---------------------------------------------------------------------------
  # Setup / teardown
  # ---------------------------------------------------------------------------

  setup_all do
    Application.put_env(:jsonl_ingestion, JsonlIngestionTest.TestRepo,
      database: ":memory:",
      pool_size: 1
    )

    {:ok, _} = JsonlIngestionTest.TestRepo.start_link()

    JsonlIngestionTest.TestRepo.query!(
      """
      CREATE TABLE events (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        event_id    TEXT    UNIQUE,
        name        TEXT    NOT NULL,
        severity    INTEGER,
        inserted_at TEXT    NOT NULL,
        updated_at  TEXT    NOT NULL
      )
      """,
      []
    )

    :ok
  end

  setup do
    TestRepo.delete_all(Event)
    :ok
  end

  # ---------------------------------------------------------------------------
  # Happy-path: fresh inserts (sequential)
  # ---------------------------------------------------------------------------

  test "inserts all records from a JSONL file sequentially" do
    records =
      Enum.map(1..12, fn i ->
        %{"event_id" => "evt-#{i}", "name" => "event #{i}", "severity" => i}
      end)

    path = tmp_path("fresh.jsonl")
    write_jsonl!(path, to_jsonl(records))

    assert {:ok, stats} =
             JsonlIngestion.ingest(TestRepo, Event, path,
               conflict_target: [:event_id],
               batch_size: 5
             )

    assert stats.total == 12
    assert stats.inserted == 12
    assert stats.skipped == 0
    assert stats.failed == 0
    assert length(all_events()) == 12
  end

  # ---------------------------------------------------------------------------
  # Parallel insertion
  # ---------------------------------------------------------------------------

  test "inserts records in parallel when max_concurrency > 1" do
    records =
      Enum.map(1..20, fn i ->
        %{"event_id" => "par-#{i}", "name" => "parallel #{i}", "severity" => i}
      end)

    path = tmp_path("parallel.jsonl")
    write_jsonl!(path, to_jsonl(records))

    assert {:ok, stats} =
             JsonlIngestion.ingest(TestRepo, Event, path,
               conflict_target: [:event_id],
               batch_size: 5,
               max_concurrency: 3
             )

    assert stats.total == 20
    assert stats.inserted == 20
    assert stats.skipped == 0
    assert stats.failed == 0
    assert length(all_events()) == 20
  end

  # ---------------------------------------------------------------------------
  # Malformed lines are skipped
  # ---------------------------------------------------------------------------

  test "skips malformed JSON lines and non-object lines" do
    lines = [
      ~s({"event_id": "evt-1", "name": "good 1", "severity": 1}),
      ~s({this is not json}),
      ~s("just a string"),
      ~s([1, 2, 3]),
      ~s({"event_id": "evt-2", "name": "good 2", "severity": 2}),
      ~s(42),
      ~s({"event_id": "evt-3", "name": "good 3", "severity": 3})
    ]

    path = tmp_path("mixed.jsonl")
    write_jsonl!(path, lines)

    assert {:ok, stats} =
             JsonlIngestion.ingest(TestRepo, Event, path,
               conflict_target: [:event_id],
               batch_size: 10
             )

    assert stats.total == 7
    assert stats.inserted == 3
    # 4 bad lines: malformed JSON, string, array, number
    assert stats.skipped == 4
    assert stats.failed == 0
    assert length(all_events()) == 3
  end

  # ---------------------------------------------------------------------------
  # Blank lines are ignored (not counted in total)
  # ---------------------------------------------------------------------------

  test "blank lines are excluded from total count" do
    lines = [
      ~s({"event_id": "evt-1", "name": "one", "severity": 1}),
      "",
      "   ",
      ~s({"event_id": "evt-2", "name": "two", "severity": 2}),
      ""
    ]

    path = tmp_path("blanks.jsonl")
    write_jsonl!(path, lines)

    assert {:ok, stats} =
             JsonlIngestion.ingest(TestRepo, Event, path, conflict_target: [:event_id])

    assert stats.total == 2
    assert stats.inserted == 2
    assert stats.skipped == 0
  end

  # ---------------------------------------------------------------------------
  # File not found
  # ---------------------------------------------------------------------------

  test "returns {:error, :file_not_found} for missing file" do
    assert {:error, :file_not_found} =
             JsonlIngestion.ingest(TestRepo, Event, "/no/such/file.jsonl")
  end

  # ---------------------------------------------------------------------------
  # Empty file
  # ---------------------------------------------------------------------------

  test "handles an empty file gracefully" do
    # TODO
  end

  # ---------------------------------------------------------------------------
  # Partial batch failure
  # ---------------------------------------------------------------------------

  test "continues processing after a failed batch and reports failures" do
    good_before =
      Enum.map(1..5, fn i ->
        %{"event_id" => "pre-#{i}", "name" => "pre #{i}", "severity" => i}
      end)

    # Records missing the required "name" field — will cause NOT NULL failure
    bad_batch =
      Enum.map(1..5, fn i ->
        %{"event_id" => "bad-#{i}", "severity" => i}
      end)

    good_after =
      Enum.map(1..5, fn i ->
        %{"event_id" => "post-#{i}", "name" => "post #{i}", "severity" => i}
      end)

    all_records = good_before ++ bad_batch ++ good_after
    path = tmp_path("partial_fail.jsonl")
    write_jsonl!(path, to_jsonl(all_records))

    # batch_size=5 means batches are: [pre-1..5], [bad-1..5], [post-1..5]
    assert {:ok, stats} =
             JsonlIngestion.ingest(TestRepo, Event, path,
               conflict_target: [:event_id],
               batch_size: 5
             )

    assert stats.total == 15
    assert stats.failed == 5
    assert stats.inserted == 10
    assert stats.skipped == 0
    assert length(all_events()) == 10
  end

  # ---------------------------------------------------------------------------
  # Upsert: duplicate event_ids are handled by on_conflict
  # ---------------------------------------------------------------------------

  test "upserts records with on_conflict: :replace_all" do
    records =
      Enum.map(1..5, fn i ->
        %{"event_id" => "dup-#{i}", "name" => "original #{i}", "severity" => i}
      end)

    path = tmp_path("upsert.jsonl")
    write_jsonl!(path, to_jsonl(records))

    # First pass
    JsonlIngestion.ingest(TestRepo, Event, path, conflict_target: [:event_id])

    # Second pass with updated names
    updated =
      Enum.map(1..5, fn i ->
        %{"event_id" => "dup-#{i}", "name" => "updated #{i}", "severity" => i * 10}
      end)

    write_jsonl!(path, to_jsonl(updated))

    assert {:ok, stats} =
             JsonlIngestion.ingest(TestRepo, Event, path,
               conflict_target: [:event_id],
               on_conflict: :replace_all
             )

    assert stats.total == 5
    assert stats.inserted == 5
    assert stats.failed == 0

    # Values should reflect the second pass
    event = TestRepo.get_by!(Event, event_id: "dup-1")
    assert event.name == "updated 1"
    assert event.severity == 10

    # Still only 5 rows total
    assert length(all_events()) == 5
  end
end
```
