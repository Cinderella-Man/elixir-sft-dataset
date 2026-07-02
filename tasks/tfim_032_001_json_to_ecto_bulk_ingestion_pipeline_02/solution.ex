  test "inserts all records from a simple JSON file" do
    records =
      Enum.map(1..10, fn i ->
        %{"external_id" => "eid-#{i}", "name" => "widget #{i}", "value" => i}
      end)

    path = tmp_path("fresh_insert.json")
    write_json!(path, records)

    assert {:ok, stats} =
             DataIngestion.ingest(TestRepo, Widget, path,
               conflict_target: [:external_id],
               batch_size: 3
             )

    assert stats.total == 10
    assert stats.inserted == 10
    assert stats.updated == 0
    assert stats.failed == 0
    assert length(all_widgets()) == 10
  end