  test "integer and float values are both accepted" do
    path = tmp_path("mixed_types")

    lines = [
      metric_line("2024-01-01T00:00:00Z", "m", 10),
      metric_line("2024-01-01T00:01:00Z", "m", 3.5)
    ]

    write_lines(path, lines)
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = MetricAggregator.summarize(path)
    assert report.per_metric["m"].count == 2
    assert report.per_metric["m"].min == 3.5
    assert report.per_metric["m"].max == 10
    assert_in_delta report.per_metric["m"].sum, 13.5, 0.001
  end