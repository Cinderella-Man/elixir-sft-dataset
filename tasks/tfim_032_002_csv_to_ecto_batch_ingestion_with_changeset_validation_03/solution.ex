  test "skips rows that fail changeset validation and reports line numbers" do
    header = ["external_id", "name", "price"]

    rows = [
      ["eid-1", "good product", "100"],
      # missing name → invalid (line 3)
      ["eid-2", "", "200"],
      # missing external_id → invalid (line 4)
      ["", "no id product", "300"],
      ["eid-4", "another good", "400"]
    ]

    path = tmp_path("validation.csv")
    write_csv!(path, header, rows)

    assert {:ok, stats} =
             CsvIngestion.ingest(TestRepo, Product, path,
               conflict_target: [:external_id],
               batch_size: 10
             )

    assert stats.total == 4
    assert stats.inserted == 2
    assert stats.invalid == 2
    assert stats.failed == 0

    # Verify line numbers are correct (header is line 1)
    error_lines = Enum.map(stats.validation_errors, &elem(&1, 0))
    assert 3 in error_lines
    assert 4 in error_lines

    assert length(all_products()) == 2
  end