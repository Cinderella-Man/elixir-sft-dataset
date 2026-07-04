  test "returns {:error, :empty_file} for a zero-byte file" do
    path = tmp_path("empty.csv")
    File.write!(path, "")

    assert {:error, :empty_file} =
             CsvIngestion.ingest(TestRepo, Product, path)
  end