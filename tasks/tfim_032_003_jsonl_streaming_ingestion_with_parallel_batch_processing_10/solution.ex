  test "keeps only declared schema fields when a record carries extra keys" do
    records =
      Enum.map(1..4, fn i ->
        %{
          "event_id" => "extra-#{i}",
          "name" => "extra #{i}",
          "severity" => i,
          "undeclared_key_alpha" => "ignore me",
          "undeclared_key_beta" => i * 100
        }
      end)

    path = tmp_path("extra_keys.jsonl")
    write_jsonl!(path, to_jsonl(records))

    assert {:ok, stats} =
             JsonlIngestion.ingest(TestRepo, Event, path,
               conflict_target: [:event_id],
               batch_size: 10
             )

    assert stats.total == 4
    assert stats.inserted == 4
    assert stats.skipped == 0
    assert stats.failed == 0

    event = TestRepo.get_by!(Event, event_id: "extra-1")
    assert event.name == "extra 1"
    assert event.severity == 1

    assert length(all_events()) == 4
  end