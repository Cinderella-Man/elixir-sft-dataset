  test "queue is strictly FIFO" do
    {:ok, kp} = KeyedPool.start_link(max_concurrency: 1)
    {:ok, order} = Agent.start_link(fn -> [] end)

    # First task grabs the slot and holds it
    blocker =
      Task.async(fn ->
        KeyedPool.execute(kp, :fifo, fn ->
          Process.sleep(300)
          Agent.update(order, fn list -> list ++ [:blocker] end)
          {:ok, :blocker}
        end)
      end)

    Process.sleep(30)

    # Queue up callers in known order
    queued =
      for label <- [:first, :second, :third] do
        Task.async(fn ->
          KeyedPool.execute(kp, :fifo, fn ->
            Agent.update(order, fn list -> list ++ [label] end)
            Process.sleep(20)
            {:ok, label}
          end)
        end)
      end

    Task.await(blocker, 5_000)
    Task.await_many(queued, 5_000)

    assert Agent.get(order, & &1) == [:blocker, :first, :second, :third]
  end