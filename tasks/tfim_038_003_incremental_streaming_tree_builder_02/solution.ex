  test "starts and reports an empty forest" do
    assert {:ok, pid} = TreeStream.start_link()
    assert TreeStream.count(pid) == 0
    assert {:ok, []} = TreeStream.forest(pid)
    TreeStream.stop(pid)
  end