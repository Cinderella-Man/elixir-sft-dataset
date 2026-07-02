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