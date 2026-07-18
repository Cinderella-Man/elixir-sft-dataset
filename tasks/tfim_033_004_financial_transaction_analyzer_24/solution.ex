  test "valid JSON that is not an object counts as malformed" do
    path = tmp_path("non_object")
    write_lines(path, ["123", "[1, 2, 3]", ~s("just a string"), "null", "true"])
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = TransactionAnalyzer.analyze(path)
    assert report.malformed_count == 5
    assert report.top_accounts == []
    assert report.time_range == nil
  end