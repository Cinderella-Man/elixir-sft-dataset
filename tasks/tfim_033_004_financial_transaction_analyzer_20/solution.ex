  test "daily_volume spans multiple calendar days" do
    path = tmp_path("multiday")

    lines = [
      txn_line("2024-01-01T23:59:00Z", "a", "credit", 100, "USD"),
      txn_line("2024-01-02T00:01:00Z", "a", "debit", 200, "USD")
    ]

    write_lines(path, lines)
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = TransactionAnalyzer.analyze(path)

    assert_in_delta report.daily_volume[{2024, 1, 1}], 100.0, 0.001
    assert_in_delta report.daily_volume[{2024, 1, 2}], 200.0, 0.001
  end