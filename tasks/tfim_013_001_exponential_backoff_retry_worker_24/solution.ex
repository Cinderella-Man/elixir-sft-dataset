  test "start_link with no arguments starts a working process", %{rw: _rw} do
    assert {:ok, pid} = RetryWorker.start_link()
    assert is_pid(pid)
    assert {:ok, :ready} = RetryWorker.execute(pid, fn -> {:ok, :ready} end)
  end