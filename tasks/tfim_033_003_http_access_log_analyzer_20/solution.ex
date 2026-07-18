  test "requests_per_minute spans multiple calendar days" do
    path = tmp_path("multiday")

    lines = [
      access_line("2024-01-01T23:59:00Z", "GET", "/a", 200, 1.0),
      access_line("2024-01-02T00:01:00Z", "GET", "/b", 200, 2.0)
    ]

    write_lines(path, lines)
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = AccessLogAnalyzer.analyze(path)

    assert report.requests_per_minute == %{
             {{2024, 1, 1}, {23, 59}} => 1,
             {{2024, 1, 2}, {0, 1}} => 1
           }
  end