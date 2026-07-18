  test "non-string timestamp values are counted as malformed" do
    path = tmp_path("nonstring_ts")

    lines = [
      log_line(1_705_327_402, "info", "numeric timestamp"),
      log_line(%{"iso" => "2024-01-15T14:03:22Z"}, "info", "object timestamp"),
      log_line("2024-01-15T14:03:22Z", "info", "good line")
    ]

    write_lines(path, lines)
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = LogAnalyzer.analyze(path)
    assert report.malformed_count == 2
    assert report.counts_by_level == %{"info" => 1}
  end