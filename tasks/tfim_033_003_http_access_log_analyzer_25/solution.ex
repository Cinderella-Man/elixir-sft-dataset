  test "non-numeric duration_ms is malformed while integer duration_ms is valid" do
    path = tmp_path("bad_duration")

    write_lines(path, [
      Jason.encode!(%{
        "timestamp" => "2024-01-15T10:00:00Z",
        "method" => "GET",
        "path" => "/slow",
        "status_code" => 200,
        "duration_ms" => "12.5"
      }),
      Jason.encode!(%{
        "timestamp" => "2024-01-15T10:00:01Z",
        "method" => "GET",
        "path" => "/int",
        "status_code" => 200,
        "duration_ms" => 7
      })
    ])

    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = AccessLogAnalyzer.analyze(path)
    assert report.malformed_count == 1
    assert report.top_paths == [{"/int", 1}]
    assert report.avg_duration == 7.0
    assert report.max_duration == {"/int", 7}
  end