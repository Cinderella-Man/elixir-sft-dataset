  test "non-string method or path makes the line malformed" do
    path = tmp_path("bad_method_path")

    write_lines(path, [
      Jason.encode!(%{
        "timestamp" => "2024-01-15T10:00:00Z",
        "method" => 123,
        "path" => "/a",
        "status_code" => 200,
        "duration_ms" => 5.0
      }),
      Jason.encode!(%{
        "timestamp" => "2024-01-15T10:00:00Z",
        "method" => "GET",
        "path" => ["/b"],
        "status_code" => 200,
        "duration_ms" => 5.0
      })
    ])

    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = AccessLogAnalyzer.analyze(path)
    assert report.malformed_count == 2
    assert report.requests_by_method == %{}
    assert report.time_range == nil
  end