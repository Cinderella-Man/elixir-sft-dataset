  test "valid JSON whose top-level value is not an object is malformed" do
    path = tmp_path("not_object")

    write_lines(path, [
      "[1, 2, 3]",
      "\"just a string\"",
      "42",
      "null",
      access_line("2024-01-15T10:00:00Z", "GET", "/ok", 200, 5.0)
    ])

    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = AccessLogAnalyzer.analyze(path)
    assert report.malformed_count == 4
    assert report.top_paths == [{"/ok", 1}]
  end