  test "start_link accepts a :name option" do
    {:ok, pid} = Watchdog.start_link(name: :custom_watchdog)
    assert is_pid(pid)
    assert Process.whereis(:custom_watchdog) == pid
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
  end