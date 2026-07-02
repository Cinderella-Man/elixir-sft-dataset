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