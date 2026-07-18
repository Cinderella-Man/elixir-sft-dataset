  test "start_link registers the process under the given name", %{bm: bm, pid: pid} do
    assert is_pid(pid)
    assert Process.alive?(pid)
    assert pid == Process.whereis(bm)
  end