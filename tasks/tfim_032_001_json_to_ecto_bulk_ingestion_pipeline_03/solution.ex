  test "updates existing records on conflict" do
    # Seed 5 rows
    seed =
      Enum.map(1..5, fn i ->
        %{"external_id" => "eid-#{i}", "name" => "old #{i}", "value" => 0}
      end)

    path = tmp_path("seed.json")
    write_json!(path, seed)
    DataIngestion.ingest(TestRepo, Widget, path, conflict_target: [:external_id])

    # Sleep long enough that the second ingest's timestamp (truncated to seconds)
    # differs from the seed's inserted_at by > @insert_window_seconds (1 s), so the
    # solution's timestamp-based classifier can tell inserts from updates.
    Process.sleep(2000)

    # Now run again: same 5 external_ids + 5 new ones
    records =
      Enum.map(1..10, fn i ->
        %{"external_id" => "eid-#{i}", "name" => "new #{i}", "value" => i * 10}
      end)

    write_json!(path, records)

    assert {:ok, stats} =
             DataIngestion.ingest(TestRepo, Widget, path,
               conflict_target: [:external_id],
               # Preserve the original inserted_at so the classifier can distinguish
               # fresh inserts (inserted_at ≈ updated_at) from updates (inserted_at
               # is 2+ seconds older than updated_at).
               on_conflict: {:replace_all_except, [:inserted_at]},
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