  test "line whose timestamp is not ISO 8601 is counted as malformed" do
    path = tmp_path("bad_timestamp")

    write_lines(path, [
      access_line("15/01/2024 14:03:22", "GET", "/a", 200, 5.0),
      access_line("not-a-timestamp", "GET", "/b", 200, 5.0),
      access_line("2024-01-15T10:00:00Z", "GET", "/ok", 200, 5.0)
    ])

    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = AccessLogAnalyzer.analyze(path)
    assert report.malformed_count == 2
    assert report.requests_by_method == %{"GET" => 1}
    assert report.top_paths == [{"/ok", 1}]
  end