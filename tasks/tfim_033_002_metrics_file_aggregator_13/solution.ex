  test "file with only malformed lines" do
    path = tmp_path("all_bad")
    write_lines(path, ["oops", "{}", ~s({"name": "x"})])
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = MetricAggregator.summarize(path)
    assert report.malformed_count == 3
    assert report.total_samples == 0
    assert report.time_range == nil
  end