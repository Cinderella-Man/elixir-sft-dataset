  test "file with only blank lines returns zero counts" do
    path = tmp_path("blanks")
    write_lines(path, ["", "   ", "\t"])
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = TransactionAnalyzer.analyze(path)
    assert report.malformed_count == 0
    assert report.time_range == nil
  end