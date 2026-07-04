  test "handles an empty file gracefully" do
    path = tmp_path("empty.jsonl")
    File.write!(path, "")

    assert {:ok, stats} = JsonlIngestion.ingest(TestRepo, Event, path)

    assert stats == %{total: 0, inserted: 0, skipped: 0, failed: 0}
    assert all_events() == []
  end