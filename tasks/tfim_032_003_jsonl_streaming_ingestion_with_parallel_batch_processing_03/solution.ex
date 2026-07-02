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