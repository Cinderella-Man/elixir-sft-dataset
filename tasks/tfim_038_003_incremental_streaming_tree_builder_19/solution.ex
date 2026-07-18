  test "stop terminates the server process" do
    {:ok, pid} = TreeStream.start_link()
    ref = Process.monitor(pid)
    assert :ok = TreeStream.stop(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1_000
    refute Process.alive?(pid)
  end