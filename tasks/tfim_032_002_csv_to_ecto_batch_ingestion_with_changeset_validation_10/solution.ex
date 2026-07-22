  test "DEFAULT options actually insert (empty conflict target is omitted)" do
    header = ["external_id", "name", "price"]
    rows = Enum.map(1..4, fn i -> ["def-#{i}", "product #{i}", "#{i * 10}"] end)

    path = tmp_path("default_opts.csv")
    write_csv!(path, header, rows)

    # No conflict options at all: the empty default target must be omitted
    # from insert_all — a naive pass-through fails every batch in the rescue.
    assert {:ok, stats} = CsvIngestion.ingest(TestRepo, Product, path)
    assert stats.inserted == 4
    assert stats.failed == 0
  end