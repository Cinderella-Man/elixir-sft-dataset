  test "single valid line produces consistent report" do
    path = tmp_path("single")
    write_lines(path, [log_line("2024-03-20T08:30:00Z", "info", "hello")])
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = LogAnalyzer.analyze(path)
    assert report.counts_by_level == %{"info" => 1}
    assert report.error_rate == 0.0
    assert report.malformed_count == 0
    {first, last} = report.time_range
    assert DateTime.compare(first, last) == :eq
  end