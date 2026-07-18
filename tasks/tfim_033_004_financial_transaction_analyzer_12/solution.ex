  test "file with only malformed lines" do
    path = tmp_path("all_bad")
    write_lines(path, ["oops", "{}", ~s({"account_id": "x"})])
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = TransactionAnalyzer.analyze(path)
    assert report.malformed_count == 3
    assert report.time_range == nil
    assert report.top_accounts == []
  end