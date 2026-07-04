  test "returns {:error, :file_not_found} for missing file" do
    assert {:error, :file_not_found} =
             CsvIngestion.ingest(TestRepo, Product, "/no/such/file.csv")
  end