  test "empty file returns zero counts" do
    path = tmp_path("empty")
    File.write!(path, "")
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = MetricAggregator.summarize(path)
    assert report.per_metric == %{}
    assert report.total_samples == 0
    assert report.time_range == nil
    assert report.samples_per_hour == %{}
    assert report.unique_tags == %{}
    assert report.malformed_count == 0
  end