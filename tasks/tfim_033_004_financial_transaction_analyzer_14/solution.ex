  test "single valid line produces consistent report" do
    path = tmp_path("single")
    write_lines(path, [txn_line("2024-03-20T08:30:00Z", "acct_x", "credit", 99.99, "USD")])
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = TransactionAnalyzer.analyze(path)
    assert_in_delta report.balance_by_account["acct_x"], 99.99, 0.001
    assert report.transaction_count == %{"credit" => 1}
    assert report.malformed_count == 0
    {first, last} = report.time_range
    assert DateTime.compare(first, last) == :eq
  end