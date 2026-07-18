  test "a crashed retry jumps ahead of an already-queued task", _context do
    pool =
      start_supervised!(
        {RetryPool, pool_size: 1, max_queue: 5, name: :added_front_pool},
        id: :added_front
      )

    {:ok, counter} = Agent.start_link(fn -> 0 end)
    collector = self()

    task_a = fn ->
      n = Agent.get_and_update(counter, fn n -> {n, n + 1} end)

      if n == 0 do
        send(collector, {:ready_a, self()})

        receive do
          :proceed -> raise "a fails first time"
        end
      else
        send(collector, {:executed, :a})
        :a_ok
      end
    end

    {:ok, _ra} = RetryPool.submit(pool, task_a, max_retries: 1)
    assert_receive {:ready_a, worker_a}, 1_000

    {:ok, _rb} =
      RetryPool.submit(pool, fn ->
        send(collector, {:executed, :b})
        :b_ok
      end)

    release(worker_a)

    assert_receive {:executed, first}, 2_000
    assert first == :a
    assert_receive {:executed, second}, 2_000
    assert second == :b

    Agent.stop(counter)
  end