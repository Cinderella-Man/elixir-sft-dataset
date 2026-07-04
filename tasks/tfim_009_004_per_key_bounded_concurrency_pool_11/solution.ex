  test "different keys have independent pools" do
    {:ok, kp} = KeyedPool.start_link(max_concurrency: 1)

    tasks =
      for key <- [:a, :b, :c] do
        Task.async(fn ->
          KeyedPool.execute(kp, key, fn ->
            Process.sleep(100)
            {:ok, key}
          end)
        end)
      end

    {elapsed, results} =
      :timer.tc(fn ->
        Task.await_many(tasks, 5_000)
      end)

    assert {:ok, :a} in results
    assert {:ok, :b} in results
    assert {:ok, :c} in results

    # With 3 independent keys at max_concurrency: 1, all should run
    # in parallel (~100ms), not serial (~300ms)
    assert elapsed < 250_000
  end