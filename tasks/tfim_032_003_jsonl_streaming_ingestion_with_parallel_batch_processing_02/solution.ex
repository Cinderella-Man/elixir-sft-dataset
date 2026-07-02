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