  test "top errors caps at 10 distinct messages" do
    path = tmp_path("top10")

    # 15 distinct error messages, each appearing once
    lines =
      for i <- 1..15 do
        log_line("2024-06-01T00:00:0#{rem(i, 10)}Z", "error", "error message #{i}")
      end

    write_lines(path, lines)
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = LogAnalyzer.analyze(path)
    assert length(report.top_errors) == 10
  end