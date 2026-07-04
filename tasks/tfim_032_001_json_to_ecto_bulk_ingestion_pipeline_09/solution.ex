  test "handles an empty JSON array gracefully" do
    path = tmp_path("empty.json")
    write_json!(path, [])

    assert {:ok, stats} = DataIngestion.ingest(TestRepo, Widget, path)

    assert stats == %{total: 0, inserted: 0, updated: 0, failed: 0}
    assert all_widgets() == []
  end