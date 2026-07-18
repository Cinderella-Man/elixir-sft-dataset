  test "status reflects running and queued counts" do
    {:ok, kp} = KeyedPool.start_link(max_concurrency: 2)

    # Start 4 tasks on the same key (2 will run, 2 will queue)
    tasks =
      for _ <- 1..4 do
        Task.async(fn ->
          KeyedPool.execute(kp, :busy, fn ->
            Process.sleep(500)
            {:ok, :done}
          end)
        end)
      end

    # Wait for all to register
    Process.sleep(50)

    status = KeyedPool.status(kp, :busy)
    assert status.running == 2
    assert status.queued == 2

    Task.await_many(tasks, 10_000)

    # After completion, key should be cleaned up
    assert KeyedPool.status(kp, :busy) == %{running: 0, queued: 0}
  end