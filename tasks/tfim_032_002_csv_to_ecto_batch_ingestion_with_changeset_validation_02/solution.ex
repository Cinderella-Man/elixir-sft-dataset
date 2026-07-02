  test "inserts all valid rows from a CSV file" do
    header = ["external_id", "name", "price"]
    rows = Enum.map(1..10, fn i -> ["eid-#{i}", "product #{i}", "#{i * 100}"] end)

    path = tmp_path("fresh_insert.csv")
    write_csv!(path, header, rows)

    assert {:ok, stats} =
             CsvIngestion.ingest(TestRepo, Product, path,
               conflict_target: [:external_id],
               batch_size: 3
             )

    assert stats.total == 10
    assert stats.inserted == 10
    assert stats.invalid == 0
    assert stats.failed == 0
    assert stats.validation_errors == []
    assert length(all_products()) == 10
  end