  test "path that exists but cannot be opened as a file returns an error tuple" do
    path = tmp_path("is_a_directory")
    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf(path) end)

    assert {:error, _reason} = TransactionAnalyzer.analyze(path)
  end