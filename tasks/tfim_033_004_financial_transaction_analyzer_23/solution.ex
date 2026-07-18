  test "daily_volume buckets an offset timestamp by its UTC day" do
    path = tmp_path("utc_day")

    write_lines(path, [
      txn_line("2024-01-15T23:30:00-05:00", "acct_o", "credit", 100, "USD")
    ])

    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = TransactionAnalyzer.analyze(path)
    assert Map.keys(report.daily_volume) == [{2024, 1, 16}]
    assert is_float(report.daily_volume[{2024, 1, 16}])
    assert_in_delta report.daily_volume[{2024, 1, 16}], 100.0, 0.001
  end