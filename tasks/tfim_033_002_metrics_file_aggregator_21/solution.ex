  test "line whose tags field is not an object is malformed" do
    path = tmp_path("bad_tags")

    write_lines(path, [
      Jason.encode!(%{
        "timestamp" => "2024-01-01T00:00:00Z",
        "name" => "x",
        "value" => 1,
        "tags" => ["a", "b"]
      }),
      Jason.encode!(%{
        "timestamp" => "2024-01-01T00:01:00Z",
        "name" => "x",
        "value" => 1,
        "tags" => "host=a"
      }),
      Jason.encode!(%{
        "timestamp" => "2024-01-01T00:02:00Z",
        "name" => "x",
        "value" => 1,
        "tags" => 7
      })
    ])

    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = MetricAggregator.summarize(path)
    assert report.malformed_count == 3
    assert report.total_samples == 0
    assert report.unique_tags == %{}
  end