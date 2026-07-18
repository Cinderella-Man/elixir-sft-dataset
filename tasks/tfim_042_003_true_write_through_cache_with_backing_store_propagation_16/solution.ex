  test "cache hits are served from ETS while the server is blocked in a loader", %{cl: cl} do
    assert {:ok, :warm} = CacheLayer.fetch(cl, :users, "warm", fn -> Store.loaded(:warm) end)

    test_pid = self()
    gate = spawn(fn -> Process.sleep(:infinity) end)

    slow_loader = fn ->
      ref = Process.monitor(gate)
      send(test_pid, :loader_running)

      receive do
        {:DOWN, ^ref, :process, _, _} -> :ok
      end

      Store.loaded(:slow)
    end

    blocked = Task.async(fn -> CacheLayer.fetch(cl, :users, "slow", slow_loader) end)
    assert_receive :loader_running, 1_000

    boom = fn -> raise "a cache hit must not call the loader" end
    reader = Task.async(fn -> CacheLayer.fetch(cl, :users, "warm", boom) end)

    assert {:ok, {:ok, :warm}} = Task.yield(reader, 500) || Task.shutdown(reader, :brutal_kill)

    Process.exit(gate, :kill)
    assert {:ok, :slow} = Task.await(blocked, 1_000)
  end