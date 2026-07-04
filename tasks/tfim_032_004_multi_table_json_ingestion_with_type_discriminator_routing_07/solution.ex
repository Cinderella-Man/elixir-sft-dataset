  test "returns {:error, :file_not_found} for missing file" do
    assert {:error, :file_not_found} =
             MultiSchemaIngestion.ingest(TestRepo, routing(), "/no/such/file.json")
  end