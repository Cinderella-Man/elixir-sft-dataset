  test "path that exists but cannot be opened as a file returns an error tuple" do
    dir = Path.join(System.tmp_dir!(), "access_log_dir_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf(dir) end)

    assert {:error, _reason} = AccessLogAnalyzer.analyze(dir)
  end