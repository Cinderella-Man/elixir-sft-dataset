  test "status_code as float is malformed" do
    path = tmp_path("float_status")

    write_lines(path, [
      Jason.encode!(%{
        "timestamp" => "2024-01-01T00:00:00Z",
        "method" => "GET",
        "path" => "/x",
        "status_code" => 200.0,
        "duration_ms" => 5
      })
    ])

    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = AccessLogAnalyzer.analyze(path)
    assert report.malformed_count == 1
  end