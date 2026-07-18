  test "single valid line produces consistent report" do
    path = tmp_path("single")
    write_lines(path, [access_line("2024-03-20T08:30:00Z", "GET", "/ping", 200, 5.0)])
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = AccessLogAnalyzer.analyze(path)
    assert report.requests_by_method == %{"GET" => 1}
    assert report.avg_duration == 5.0
    assert report.max_duration == {"/ping", 5.0}
    assert report.error_rate == 0.0
    assert report.malformed_count == 0
    {first, last} = report.time_range
    assert DateTime.compare(first, last) == :eq
  end