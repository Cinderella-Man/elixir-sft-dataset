  test "start_link/1 registers the process under a custom :name" do
    # The default name is already covered by the suite's setup; here the
    # :name option must actually drive registration.
    name = :"max_wait_debouncer_#{System.pid()}_#{System.unique_integer([:positive])}"

    assert {:ok, pid} = MaxWaitDebouncer.start_link(name: name)
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)

    assert Process.alive?(pid)
    assert Process.whereis(name) == pid
  end