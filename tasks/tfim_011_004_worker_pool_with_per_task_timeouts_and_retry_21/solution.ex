  test "a timed-out retry runs before an already-queued task", _context do
    pool =
      start_supervised!(
        {RetryPool, pool_size: 1, max_queue: 5, name: :added_to_front_pool},
        id: :added_to_front
      )

    {:ok, counter} = Agent.start_link(fn -> 0 end)
    collector = self()

    task_a = fn ->
      n = Agent.get_and_update(counter, fn n -> {n, n + 1} end)

      if n == 0 do
        Process.sleep(2_000)
        :a_slow
      else
        send(collector, {:executed, :a})
        :a_ok
      end
    end

    {:ok, _ra} = RetryPool.submit(pool, task_a, task_timeout: 200, max_retries: 1)

    {:ok, _rb} =
      RetryPool.submit(pool, fn ->
        send(collector, {:executed, :b})
        :b_ok
      end)

    assert_receive {:executed, first}, 3_000
    assert first == :a
    assert_receive {:executed, second}, 3_000
    assert second == :b

    Agent.stop(counter)
  end