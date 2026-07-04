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
             JsonlIngestion.ingest(TestRepo, Event, path,
               conflict_target: [:event_id]
             )

    assert stats.total == 2
    assert stats.inserted == 2
    assert stats.skipped == 0
  end