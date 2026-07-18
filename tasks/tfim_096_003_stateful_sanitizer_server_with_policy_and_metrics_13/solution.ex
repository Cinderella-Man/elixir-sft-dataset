  test "server started with :name is reachable through the public API by that name" do
    name = :sanitizer_named_server_audit
    assert {:ok, pid} = Sanitizer.start_link(name: name, max_filename_length: 4)
    assert Process.whereis(name) == pid

    assert {:ok, "_9x"} = Sanitizer.sanitize_identifier(name, "9x!")
    assert {:ok, "abcd"} = Sanitizer.sanitize_filename(name, "abcdefg")

    m = Sanitizer.metrics(name)
    assert m.identifiers == 1
    assert m.filenames == 1
    assert m.filenames_truncated == 1

    assert :ok = Sanitizer.reset_metrics(name)
    assert Sanitizer.metrics(name).identifiers == 0
  end