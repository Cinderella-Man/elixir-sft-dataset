  test "line with unparsable timestamp is counted as malformed" do
    path = tmp_path("bad_timestamp")

    write_lines(path, [
      Jason.encode!(%{
        "timestamp" => "not-a-real-datetime",
        "name" => "x",
        "value" => 1,
        "tags" => %{}
      }),
      Jason.encode!(%{
        "timestamp" => "2024-13-45T99:99:99Z",
        "name" => "x",
        "value" => 1,
        "tags" => %{}
      })
    ])

    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = MetricAggregator.summarize(path)
    assert report.malformed_count == 2
    assert report.total_samples == 0
    assert report.per_metric == %{}
    assert report.time_range == nil
  end