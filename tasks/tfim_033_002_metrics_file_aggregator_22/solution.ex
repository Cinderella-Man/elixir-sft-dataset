  test "lines whose top-level JSON value is not an object are malformed" do
    path = tmp_path("not_object")
    write_lines(path, ["[1, 2, 3]", "42", "\"hello\"", "true", "null"])
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = MetricAggregator.summarize(path)
    assert report.malformed_count == 5
    assert report.total_samples == 0
    assert report.time_range == nil
  end