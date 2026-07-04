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