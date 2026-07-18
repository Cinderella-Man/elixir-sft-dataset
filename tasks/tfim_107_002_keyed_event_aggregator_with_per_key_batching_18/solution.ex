  test "start_link/0 works with no argument and still accepts pushes returning :ok" do
    {:ok, pid} = KeyedAggregator.start_link()
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)

    assert Process.alive?(pid)
    assert KeyedAggregator.push(pid, {:any, "term"}, %{payload: [1, 2]}) == :ok
    assert Process.alive?(pid)
  end