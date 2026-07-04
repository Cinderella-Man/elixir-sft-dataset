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