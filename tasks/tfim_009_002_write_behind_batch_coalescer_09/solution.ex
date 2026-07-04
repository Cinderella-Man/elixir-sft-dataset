  test "different keys have independent batches", %{bc: bc} do
    {:ok, counter} = Agent.start_link(fn -> %{} end)

    flush_fn = fn items ->
      key = hd(items)

      Agent.update(counter, fn map ->
        Map.update(map, key, 1, &(&1 + 1))
      end)

      {:ok, key}
    end

    tasks =
      for key <- [:a, :b, :c] do
        Task.async(fn ->
          BatchCollector.submit(bc, key, key, flush_fn)
        end)
      end

    results = Task.await_many(tasks, 5_000)

    assert {:ok, :a} in results
    assert {:ok, :b} in results
    assert {:ok, :c} in results

    counts = Agent.get(counter, & &1)
    assert counts[:a] == 1
    assert counts[:b] == 1
    assert counts[:c] == 1
  end