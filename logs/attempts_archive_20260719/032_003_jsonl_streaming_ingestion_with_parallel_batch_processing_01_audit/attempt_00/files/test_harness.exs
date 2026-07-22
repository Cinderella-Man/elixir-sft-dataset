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
    path = tmp_path("empty.jsonl")
    File.write!(path, "")

    assert {:ok, stats} = JsonlIngestion.ingest(TestRepo, Event, path)

    assert stats == %{total: 0, inserted: 0, skipped: 0, failed: 0}
    assert all_events() == []
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

  test "defaults on_conflict to :replace_all when the option is omitted" do
    first =
      Enum.map(1..3, fn i ->
        %{"event_id" => "oc-#{i}", "name" => "first #{i}", "severity" => i}
      end)

    path = tmp_path("default_on_conflict.jsonl")
    write_jsonl!(path, to_jsonl(first))

    assert {:ok, _} = JsonlIngestion.ingest(TestRepo, Event, path, conflict_target: [:event_id])

    second =
      Enum.map(1..3, fn i ->
        %{"event_id" => "oc-#{i}", "name" => "second #{i}", "severity" => i * 100}
      end)

    write_jsonl!(path, to_jsonl(second))

    # No :on_conflict passed — the documented default must upsert, not fail.
    assert {:ok, stats} =
             JsonlIngestion.ingest(TestRepo, Event, path, conflict_target: [:event_id])

    assert stats.inserted == 3
    assert stats.failed == 0
    assert length(all_events()) == 3

    event = TestRepo.get_by!(Event, event_id: "oc-1")
    assert event.name == "second 1"
    assert event.severity == 100
  end

  test "counts failed records and keeps going when a batch fails in parallel mode" do
    good_before =
      Enum.map(1..5, fn i ->
        %{"event_id" => "ppre-#{i}", "name" => "pre #{i}", "severity" => i}
      end)

    bad_batch =
      Enum.map(1..5, fn i ->
        %{"event_id" => "pbad-#{i}", "severity" => i}
      end)

    good_after =
      Enum.map(1..5, fn i ->
        %{"event_id" => "ppost-#{i}", "name" => "post #{i}", "severity" => i}
      end)

    path = tmp_path("parallel_fail.jsonl")
    write_jsonl!(path, to_jsonl(good_before ++ bad_batch ++ good_after))

    assert {:ok, stats} =
             JsonlIngestion.ingest(TestRepo, Event, path,
               conflict_target: [:event_id],
               batch_size: 5,
               max_concurrency: 3
             )

    assert stats.total == 15
    assert stats.skipped == 0
    assert stats.failed == 5
    assert stats.inserted == 10
    assert length(all_events()) == 10
  end

  test "keeps only the current batch resident when inserting the first batch" do
    Process.register(self(), :jsonl_mem_probe)

    defmodule MemProbeRepo do
      def insert_all(_schema, rows, _opts) do
        :erlang.garbage_collect(self())
        {:memory, bytes} = :erlang.process_info(self(), :memory)
        send(:jsonl_mem_probe, {:mem, bytes})
        {length(rows), nil}
      end
    end

    records =
      Enum.map(1..50_000, fn i ->
        %{"event_id" => "mem-#{i}", "name" => "row #{i}", "severity" => rem(i, 7)}
      end)

    path = tmp_path("memory.jsonl")
    write_jsonl!(path, to_jsonl(records))

    assert {:ok, stats} = JsonlIngestion.ingest(MemProbeRepo, Event, path)
    assert stats.total == 50_000

    # A streaming pipeline holds ~batch_size rows; buffering the whole file holds 50k.
    assert_receive {:mem, bytes}
    assert bytes < 4_000_000

    Process.unregister(:jsonl_mem_probe)
  end

  test "drops JSON keys that are not declared as schema fields" do
    records = [
      %{
        "event_id" => "extra-1",
        "name" => "with extras",
        "severity" => 1,
        "not_a_field" => "junk",
        "nested" => %{"a" => 1}
      },
      %{"event_id" => "extra-2", "name" => "plain", "severity" => 2}
    ]

    path = tmp_path("extra_fields.jsonl")
    write_jsonl!(path, to_jsonl(records))

    assert {:ok, stats} =
             JsonlIngestion.ingest(TestRepo, Event, path, conflict_target: [:event_id])

    assert stats.total == 2
    assert stats.inserted == 2
    assert stats.skipped == 0
    assert stats.failed == 0

    event = TestRepo.get_by!(Event, event_id: "extra-1")
    assert event.name == "with extras"
    assert event.severity == 1
    refute is_nil(event.inserted_at)
  end

  test "collects 500 records per insert_all call when batch_size is omitted" do
    Process.register(self(), :jsonl_batch_probe)

    defmodule BatchSizeProbeRepo do
      def insert_all(_schema, rows, _opts) do
        send(:jsonl_batch_probe, {:batch, length(rows)})
        {length(rows), nil}
      end
    end

    records =
      Enum.map(1..600, fn i ->
        %{"event_id" => "bs-#{i}", "name" => "row #{i}", "severity" => i}
      end)

    path = tmp_path("default_batch_size.jsonl")
    write_jsonl!(path, to_jsonl(records))

    assert {:ok, stats} = JsonlIngestion.ingest(BatchSizeProbeRepo, Event, path)
    assert stats.total == 600
    assert stats.inserted == 600

    assert_receive {:batch, 500}
    assert_receive {:batch, 100}
    refute_receive {:batch, _}, 50

    Process.unregister(:jsonl_batch_probe)
  end

  test "passes conflict_target: :nothing to insert_all when the option is omitted" do
    Process.register(self(), :jsonl_opts_probe)

    defmodule OptsProbeRepo do
      def insert_all(_schema, rows, opts) do
        send(:jsonl_opts_probe, {:opts, opts})
        {length(rows), nil}
      end
    end

    records = [%{"event_id" => "ct-1", "name" => "one", "severity" => 1}]
    path = tmp_path("default_conflict_target.jsonl")
    write_jsonl!(path, to_jsonl(records))

    assert {:ok, stats} = JsonlIngestion.ingest(OptsProbeRepo, Event, path)
    assert stats.total == 1

    assert_receive {:opts, opts}
    assert Keyword.fetch!(opts, :conflict_target) == :nothing
    assert Keyword.fetch!(opts, :on_conflict) == :replace_all

    Process.unregister(:jsonl_opts_probe)
  end
end
