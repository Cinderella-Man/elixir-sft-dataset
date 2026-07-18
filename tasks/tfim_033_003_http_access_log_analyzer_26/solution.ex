  test "error_rate treats status_code exactly 400 as an error and 399 as success" do
    path = tmp_path("status_boundary")

    write_lines(path, [
      access_line("2024-01-15T10:00:00Z", "GET", "/a", 399, 1.0),
      access_line("2024-01-15T10:00:01Z", "GET", "/b", 400, 1.0),
      access_line("2024-01-15T10:00:02Z", "GET", "/c", 401, 1.0)
    ])

    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = AccessLogAnalyzer.analyze(path)
    assert_in_delta report.error_rate, 2 / 3, 0.0001
  end