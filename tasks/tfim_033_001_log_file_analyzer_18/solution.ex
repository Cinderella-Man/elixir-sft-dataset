  test "valid JSON that is not a top-level object counts as malformed" do
    path = tmp_path("not_object")

    write_lines(path, ["[1, 2, 3]", "\"just a string\"", "42", "null", "true"])
    on_exit(fn -> File.rm(path) end)

    assert {:ok, report} = LogAnalyzer.analyze(path)
    assert report.malformed_count == 5
    assert report.counts_by_level == %{}
    assert report.error_rate == 0.0
    assert report.time_range == nil
  end