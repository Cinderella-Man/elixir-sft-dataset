  test "start_link accepts a :name option" do
    {:ok, pid} = EscalatingWatchdog.start_link(name: :custom_escalating)
    assert is_pid(pid)
    assert Process.whereis(:custom_escalating) == pid
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
  end