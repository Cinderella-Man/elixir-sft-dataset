  test "start_link accepts a :name option" do
    {:ok, pid} = GraceWatchdog.start_link(name: :custom_grace)
    assert is_pid(pid)
    assert Process.whereis(:custom_grace) == pid
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
  end