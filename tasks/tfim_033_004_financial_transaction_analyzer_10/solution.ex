  test "empty file returns zero counts" do
    path = tmp_path("empty")
    File.write!(path, "")
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = TransactionAnalyzer.analyze(path)
    assert report.balance_by_account == %{}
    assert report.volume_by_currency == %{}
    assert report.transaction_count == %{}
    assert report.top_accounts == []
    assert report.daily_volume == %{}
    assert report.time_range == nil
    assert report.malformed_count == 0
  end