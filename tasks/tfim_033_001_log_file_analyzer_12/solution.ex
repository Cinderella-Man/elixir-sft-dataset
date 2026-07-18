  test "file with only malformed lines" do
    path = tmp_path("all_bad")
    write_lines(path, ["oops", "{}", ~s({"ts": "x"})])
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = LogAnalyzer.analyze(path)
    assert report.malformed_count == 3
    assert report.error_rate == 0.0
    assert report.time_range == nil
  end