  test "samples_per_hour spans multiple calendar days" do
    path = tmp_path("multiday")

    lines = [
      metric_line("2024-01-01T23:59:00Z", "x", 1),
      metric_line("2024-01-02T00:01:00Z", "x", 2)
    ]

    write_lines(path, lines)
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = MetricAggregator.summarize(path)

    assert report.samples_per_hour == %{
             {{2024, 1, 1}, 23} => 1,
             {{2024, 1, 2}, 0} => 1
           }
  end