  test "respects batch_size: processes all valid records across multiple batches" do
    header = ["external_id", "name", "price"]
    rows = Enum.map(1..22, fn i -> ["b-#{i}", "batch #{i}", "#{i}"] end)

    path = tmp_path("batches.csv")
    write_csv!(path, header, rows)

    assert {:ok, stats} =
             CsvIngestion.ingest(TestRepo, Product, path,
               conflict_target: [:external_id],
               batch_size: 7
             )

    assert stats.total == 22
    assert stats.inserted == 22
    assert stats.failed == 0
    assert length(all_products()) == 22
  end