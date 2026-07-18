  test "path that exists but cannot be opened returns an error tuple" do
    dir =
      Path.join(
        System.tmp_dir!(),
        "log_analyzer_test_dir_#{System.pid()}_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)

    assert {:error, _reason} = LogAnalyzer.analyze(dir)
  end