  test "handles a CSV file with only a header row" do
    path = tmp_path("header_only.csv")
    File.write!(path, "external_id,name,price\n")

    assert {:ok, stats} = CsvIngestion.ingest(TestRepo, Product, path)

    assert stats.total == 0
    assert stats.inserted == 0
    assert stats.invalid == 0
    assert stats.failed == 0
    assert all_products() == []
  end