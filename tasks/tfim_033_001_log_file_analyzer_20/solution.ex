  test "timestamps with offsets bucket into their UTC hour and time range" do
    path = tmp_path("offsets")

    lines = [
      log_line("2024-05-01T01:30:00+02:00", "error", "east of utc"),
      log_line("2024-05-01T00:30:00-05:00", "error", "west of utc")
    ]

    write_lines(path, lines)
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = LogAnalyzer.analyze(path)

    assert report.errors_per_hour == %{
             {{2024, 4, 30}, 23} => 1,
             {{2024, 5, 1}, 5} => 1
           }

    {:ok, expected_first, _} = DateTime.from_iso8601("2024-04-30T23:30:00Z")
    {:ok, expected_last, _} = DateTime.from_iso8601("2024-05-01T05:30:00Z")
    {first, last} = report.time_range
    assert DateTime.compare(first, expected_first) == :eq
    assert DateTime.compare(last, expected_last) == :eq
  end