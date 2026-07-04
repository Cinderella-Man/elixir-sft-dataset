  test "returns {:error, :file_not_found} for missing file" do
    assert {:error, :file_not_found} =
             JsonlIngestion.ingest(TestRepo, Event, "/no/such/file.jsonl")
  end