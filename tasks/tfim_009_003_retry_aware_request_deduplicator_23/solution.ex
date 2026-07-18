  test "a joining caller during retries does not spawn an extra execution", %{rd: rd} do
    test = self()

    func = fn ->
      send(test, {:running, self()})

      receive do
        :fail -> {:error, :again}
        :succeed -> {:ok, :done}
      end
    end

    t1 =
      Task.async(fn ->
        RetryDedup.execute(rd, "no_restart", func, max_retries: 5, base_delay_ms: 1)
      end)

    assert_receive {:running, p1}, 2_000
    send(p1, :fail)

    # Second caller joins while the retry sequence is in flight.
    assert_receive {:running, p2}, 2_000

    t2 =
      Task.async(fn ->
        RetryDedup.execute(rd, "no_restart", func, max_retries: 5, base_delay_ms: 1)
      end)

    send(p2, :fail)
    assert_receive {:running, p3}, 2_000
    send(p3, :fail)
    assert_receive {:running, p4}, 2_000
    send(p4, :succeed)

    assert {:ok, :done} = Task.await(t1, 5_000)
    assert {:ok, :done} = Task.await(t2, 5_000)

    # A restart would have produced a fifth invocation of func.
    refute_receive {:running, _}, 300
  end