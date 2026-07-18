  test "max_duration tie is broken alphabetically by path" do
    path = tmp_path("tie")

    lines = [
      access_line("2024-01-01T00:00:00Z", "GET", "/z", 200, 100.0),
      access_line("2024-01-01T00:01:00Z", "GET", "/a", 200, 100.0)
    ]

    write_lines(path, lines)
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = AccessLogAnalyzer.analyze(path)
    assert report.max_duration == {"/a", 100.0}
  end