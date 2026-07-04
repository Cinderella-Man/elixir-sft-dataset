  test "returns {:error, :file_not_found} for missing file" do
    assert {:error, :file_not_found} =
             DataIngestion.ingest(TestRepo, Widget, "/no/such/file.json")
  end