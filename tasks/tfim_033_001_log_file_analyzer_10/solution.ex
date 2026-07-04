  test "empty file returns zero counts" do
    path = tmp_path("empty")
    File.write!(path, "")
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = LogAnalyzer.analyze(path)
    assert report.counts_by_level == %{}
    assert report.error_rate == 0.0
    assert report.top_errors == []
    assert report.time_range == nil
    assert report.errors_per_hour == %{}
    assert report.malformed_count == 0
  end