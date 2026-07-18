  test "handles many callers across many keys" do
    {:ok, kp} = KeyedPool.start_link(max_concurrency: 3)

    tasks =
      for key <- [:a, :b, :c, :d], i <- 1..10 do
        Task.async(fn ->
          KeyedPool.execute(kp, key, fn ->
            Process.sleep(10)
            {:ok, {key, i}}
          end)
        end)
      end

    results = Task.await_many(tasks, 30_000)

    assert length(results) == 40
    assert Enum.all?(results, &match?({:ok, {_, _}}, &1))
  end