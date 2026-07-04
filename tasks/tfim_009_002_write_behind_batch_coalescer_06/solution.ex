  test "items arrive in submission order", %{bc: bc} do
    tasks =
      for i <- 1..5 do
        Task.async(fn ->
          BatchCollector.submit(bc, :order, i, fn items -> {:ok, items} end)
        end)
      end

    Process.sleep(50)

    results = Task.await_many(tasks, 5_000)

    {:ok, items} = hd(results)
    assert items == Enum.sort(items)
  end