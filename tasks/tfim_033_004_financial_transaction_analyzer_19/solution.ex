  test "debit produces negative balance" do
    path = tmp_path("neg_balance")

    write_lines(path, [
      txn_line("2024-01-01T00:00:00Z", "acct_x", "debit", 500.00, "USD")
    ])

    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = TransactionAnalyzer.analyze(path)
    assert_in_delta report.balance_by_account["acct_x"], -500.00, 0.001
  end