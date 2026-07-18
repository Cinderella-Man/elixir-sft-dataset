  test "single valid line produces consistent report" do
    path = tmp_path("single")
    write_lines(path, [metric_line("2024-03-20T08:30:00Z", "latency", 42.5, %{"env" => "prod"})])
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = MetricAggregator.summarize(path)
    assert report.per_metric["latency"].count == 1
    assert_in_delta report.per_metric["latency"].mean, 42.5, 0.001
    assert report.total_samples == 1
    assert report.malformed_count == 0
    {first, last} = report.time_range
    assert DateTime.compare(first, last) == :eq
  end