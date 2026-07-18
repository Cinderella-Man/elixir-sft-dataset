  test "file with only malformed lines" do
    path = tmp_path("all_bad")
    write_lines(path, ["oops", "{}", ~s({"method": "GET"})])
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = AccessLogAnalyzer.analyze(path)
    assert report.malformed_count == 3
    assert report.avg_duration == 0.0
    assert report.time_range == nil
  end