  test "empty file returns zero counts" do
    path = tmp_path("empty")
    File.write!(path, "")
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = AccessLogAnalyzer.analyze(path)
    assert report.requests_by_method == %{}
    assert report.requests_by_status == %{}
    assert report.top_paths == []
    assert report.avg_duration == 0.0
    assert report.max_duration == nil
    assert report.error_rate == 0.0
    assert report.time_range == nil
    assert report.requests_per_minute == %{}
    assert report.malformed_count == 0
  end