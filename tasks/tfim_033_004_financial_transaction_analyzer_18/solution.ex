  test "top_accounts caps at 5 when more accounts exist" do
    path = tmp_path("top5")

    lines =
      for i <- 1..8 do
        txn_line("2024-06-01T00:00:0#{rem(i, 10)}Z", "acct_#{i}", "credit", i * 100, "USD")
      end

    write_lines(path, lines)
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = TransactionAnalyzer.analyze(path)
    assert length(report.top_accounts) == 5
  end