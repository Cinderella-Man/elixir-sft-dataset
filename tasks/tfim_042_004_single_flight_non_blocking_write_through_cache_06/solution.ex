  test "a slow load for one key does not block loads for another key", %{cl: cl} do
    parent = self()

    # Leader for :a announces itself and blocks until told to proceed.
    slow_a = fn ->
      send(parent, {:a_leading, self()})

      receive do
        :go -> :val_a
      end
    end

    task_a = Task.async(fn -> CacheLayer.fetch(cl, :t, :a, slow_a) end)

    a_pid =
      receive do
        {:a_leading, pid} -> pid
      after
        1_000 -> flunk("leader for :a never started")
      end

    # While :a's fallback is blocked (running OUTSIDE the GenServer), a fetch
    # for a different key must complete promptly.
    assert {:ok, :val_b} = CacheLayer.fetch(cl, :t, :b, fn -> :val_b end)

    # Release :a and confirm it resolves.
    send(a_pid, :go)
    assert {:ok, :val_a} = Task.await(task_a)
  end