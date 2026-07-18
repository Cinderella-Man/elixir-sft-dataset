  test "line with empty name string is malformed" do
    path = tmp_path("empty_name")

    write_lines(path, [
      Jason.encode!(%{
        "timestamp" => "2024-01-01T00:00:00Z",
        "name" => "",
        "value" => 1,
        "tags" => %{}
      })
    ])

    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = MetricAggregator.summarize(path)
    assert report.malformed_count == 1
    assert report.total_samples == 0
  end