  test "line with string value is malformed" do
    path = tmp_path("string_value")

    write_lines(path, [
      Jason.encode!(%{
        "timestamp" => "2024-01-01T00:00:00Z",
        "name" => "x",
        "value" => "not_a_number",
        "tags" => %{}
      })
    ])

    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = MetricAggregator.summarize(path)
    assert report.malformed_count == 1
    assert report.total_samples == 0
  end