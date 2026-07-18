  test "errors_per_hour spans multiple calendar days correctly" do
    path = tmp_path("multiday")

    lines = [
      log_line("2024-01-01T23:59:00Z", "error", "midnight error"),
      log_line("2024-01-02T00:01:00Z", "error", "new day error")
    ]

    write_lines(path, lines)
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = LogAnalyzer.analyze(path)

    assert report.errors_per_hour == %{
             {{2024, 1, 1}, 23} => 1,
             {{2024, 1, 2}, 0} => 1
           }
  end