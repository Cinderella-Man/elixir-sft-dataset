  test "top_paths caps at 10 distinct paths" do
    path = tmp_path("top10")

    lines =
      for i <- 1..15 do
        access_line("2024-06-01T00:00:0#{rem(i, 10)}Z", "GET", "/path/#{i}", 200, 1.0)
      end

    write_lines(path, lines)
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = AccessLogAnalyzer.analyze(path)
    assert length(report.top_paths) == 10
  end