  test "status reports 1-based attempt number at the first retry", %{rd: rd} do
    test = self()

    func = fn ->
      send(test, {:running, self()})

      receive do
        :fail -> {:error, :again}
        :succeed -> {:ok, :done}
      end
    end

    t =
      Task.async(fn ->
        RetryDedup.execute(rd, "attempt_num", func, max_retries: 4, base_delay_ms: 1)
      end)

    # Initial attempt (attempt 0) — status is still :idle here.
    assert_receive {:running, p1}, 2_000
    send(p1, :fail)

    # First retry is attempt 1, not attempt 0.
    assert_receive {:running, p2}, 2_000
    assert RetryDedup.status(rd, "attempt_num") == {:retrying, 1, 4}
    send(p2, :fail)

    # Second retry is attempt 2.
    assert_receive {:running, p3}, 2_000
    assert RetryDedup.status(rd, "attempt_num") == {:retrying, 2, 4}
    send(p3, :succeed)

    assert {:ok, :done} = Task.await(t, 5_000)
  end