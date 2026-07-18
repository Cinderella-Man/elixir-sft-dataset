  test "top_accounts breaks equal-volume ties alphabetically by account_id" do
    path = tmp_path("ties")

    write_lines(path, [
      txn_line("2024-02-01T00:00:00Z", "acct_b", "credit", 100, "USD"),
      txn_line("2024-02-01T00:00:01Z", "acct_a", "credit", 60, "USD"),
      txn_line("2024-02-01T00:00:02Z", "acct_a", "debit", 40, "USD"),
      txn_line("2024-02-01T00:00:03Z", "acct_c", "credit", 500, "USD")
    ])

    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = TransactionAnalyzer.analyze(path)
    assert [{"acct_c", _}, {"acct_a", vol_a}, {"acct_b", vol_b}] = report.top_accounts
    assert_in_delta vol_a, 100.0, 0.001
    assert_in_delta vol_b, 100.0, 0.001
  end