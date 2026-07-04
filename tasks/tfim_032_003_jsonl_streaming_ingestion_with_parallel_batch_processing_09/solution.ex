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