  test "start_link accepts a :name option" do
    {:ok, pid} = RecurringWatchdog.start_link(name: :custom_recurring)
    assert is_pid(pid)
    assert Process.whereis(:custom_recurring) == pid
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
  end