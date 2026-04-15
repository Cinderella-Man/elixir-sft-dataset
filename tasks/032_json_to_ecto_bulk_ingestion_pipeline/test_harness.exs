defmodule DataIngestionTest do
  use ExUnit.Case, async: false

  # ---------------------------------------------------------------------------
  # Minimal in-memory Ecto setup
  # ---------------------------------------------------------------------------

  # We use the Ecto sandbox with an SQLite3 (or PG) test repo.
  # The schema below must match whatever table your migration creates.

  defmodule TestRepo do
    use Ecto.Repo, otp_app: :data_ingestion, adapter: Ecto.Adapters.SQLite3
  end

  defmodule Widget do
    use Ecto.Schema
    import Ecto.Changeset

    @primary_key {:id, :id, autogenerate: true}

    schema "widgets" do
      field(:external_id, :string)
      field(:name, :string)
      field(:value, :integer)
      timestamps()
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp write_json!(path, data) do
    File.write!(path, Jason.encode!(data))
  end

  defp tmp_path(name), do: Path.join(System.tmp_dir!(), name)

  defp all_widgets, do: TestRepo.all(Widget)

  # ---------------------------------------------------------------------------
  # Setup / teardown
  # ---------------------------------------------------------------------------

  setup do
    # Truncate table before each test
    TestRepo.delete_all(Widget)
    :ok
  end

  # ---------------------------------------------------------------------------
  # Happy-path: fresh inserts
  # ---------------------------------------------------------------------------

  test "inserts all records from a simple JSON file" do
    records =
      Enum.map(1..10, fn i ->
        %{"external_id" => "eid-#{i}", "name" => "widget #{i}", "value" => i}
      end)

    path = tmp_path("fresh_insert.json")
    write_json!(path, records)

    assert {:ok, stats} =
             DataIngestion.ingest(TestRepo, Widget, path,
               conflict_target: [:external_id],
               batch_size: 3
             )

    assert stats.total == 10
    assert stats.inserted == 10
    assert stats.updated == 0
    assert stats.failed == 0
    assert length(all_widgets()) == 10
  end

  # ---------------------------------------------------------------------------
  # Upsert: duplicates become updates
  # ---------------------------------------------------------------------------

  test "updates existing records on conflict" do
    # Seed 5 rows
    seed =
      Enum.map(1..5, fn i ->
        %{"external_id" => "eid-#{i}", "name" => "old #{i}", "value" => 0}
      end)

    path = tmp_path("seed.json")
    write_json!(path, seed)
    DataIngestion.ingest(TestRepo, Widget, path, conflict_target: [:external_id])

    # Now run again: same 5 external_ids + 5 new ones
    records =
      Enum.map(1..10, fn i ->
        %{"external_id" => "eid-#{i}", "name" => "new #{i}", "value" => i * 10}
      end)

    write_json!(path, records)

    assert {:ok, stats} =
             DataIngestion.ingest(TestRepo, Widget, path,
               conflict_target: [:external_id],
               batch_size: 4
             )

    assert stats.total == 10
    assert stats.failed == 0
    # 5 new + 5 existing  → inserts + updates = 10
    assert stats.inserted + stats.updated == 10
    assert stats.updated >= 5

    # Values in DB should reflect the new run
    widget = TestRepo.get_by!(Widget, external_id: "eid-1")
    assert widget.name == "new 1"
    assert widget.value == 10
  end

  # ---------------------------------------------------------------------------
  # Batching
  # ---------------------------------------------------------------------------

  test "respects batch_size: processes all records across multiple batches" do
    records =
      Enum.map(1..25, fn i ->
        %{"external_id" => "b-#{i}", "name" => "b #{i}", "value" => i}
      end)

    path = tmp_path("batches.json")
    write_json!(path, records)

    assert {:ok, stats} =
             DataIngestion.ingest(TestRepo, Widget, path,
               conflict_target: [:external_id],
               batch_size: 7
             )

    assert stats.total == 25
    assert stats.inserted == 25
    assert stats.failed == 0
    assert length(all_widgets()) == 25
  end

  # ---------------------------------------------------------------------------
  # Graceful error: file not found
  # ---------------------------------------------------------------------------

  test "returns {:error, :file_not_found} for missing file" do
    assert {:error, :file_not_found} =
             DataIngestion.ingest(TestRepo, Widget, "/no/such/file.json")
  end

  # ---------------------------------------------------------------------------
  # Graceful error: malformed JSON
  # ---------------------------------------------------------------------------

  test "returns {:error, :invalid_json} for a malformed JSON file" do
    path = tmp_path("bad.json")
    File.write!(path, "{this is not json}")

    assert {:error, :invalid_json} =
             DataIngestion.ingest(TestRepo, Widget, path)
  end

  # ---------------------------------------------------------------------------
  # Graceful error: valid JSON but not an array
  # ---------------------------------------------------------------------------

  test "returns {:error, :not_a_list} when the JSON root is not an array" do
    path = tmp_path("object.json")
    write_json!(path, %{"key" => "value"})

    assert {:error, :not_a_list} =
             DataIngestion.ingest(TestRepo, Widget, path)
  end

  # ---------------------------------------------------------------------------
  # Partial failure: bad batch doesn't abort the rest
  # ---------------------------------------------------------------------------

  test "continues processing after a failed batch and reports failures" do
    # 10 valid records + 1 batch that will fail due to a nil non-nullable field,
    # then 10 more valid records.
    # We simulate a bad batch by monkey-patching — instead, we pass records
    # missing a required DB field in one specific batch.
    # Here we rely on the implementation failing gracefully.

    good_before =
      Enum.map(1..10, fn i ->
        %{"external_id" => "pre-#{i}", "name" => "pre #{i}", "value" => i}
      end)

    # These records are missing the "name" field; if "name" has a NOT NULL
    # constraint they will cause the batch to fail.
    bad_batch =
      Enum.map(1..5, fn i ->
        %{"external_id" => "bad-#{i}", "value" => i}
      end)

    good_after =
      Enum.map(1..10, fn i ->
        %{"external_id" => "post-#{i}", "name" => "post #{i}", "value" => i}
      end)

    path = tmp_path("partial_fail.json")
    write_json!(path, good_before ++ bad_batch ++ good_after)

    # batch_size=5 means batches are:
    #   [pre-1..5], [pre-6..10], [bad-1..5], [post-1..5], [post-6..10]
    assert {:ok, stats} =
             DataIngestion.ingest(TestRepo, Widget, path,
               conflict_target: [:external_id],
               batch_size: 5
             )

    assert stats.total == 25
    # the bad batch
    assert stats.failed == 5
    assert stats.inserted == 20
    assert length(all_widgets()) == 20
  end

  # ---------------------------------------------------------------------------
  # Empty file (valid JSON empty array)
  # ---------------------------------------------------------------------------

  test "handles an empty JSON array gracefully" do
    path = tmp_path("empty.json")
    write_json!(path, [])

    assert {:ok, stats} = DataIngestion.ingest(TestRepo, Widget, path)

    assert stats == %{total: 0, inserted: 0, updated: 0, failed: 0}
    assert all_widgets() == []
  end
end
