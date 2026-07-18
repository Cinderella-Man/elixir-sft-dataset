  test "GenServer is not blocked during flush", %{bc: bc} do
    slow_task =
      Task.async(fn ->
        BatchCollector.submit(bc, :slow, :item, fn _items ->
          Process.sleep(500)
          {:ok, :slow_done}
        end)
      end)

    Process.sleep(50)

    {elapsed, result} =
      :timer.tc(fn ->
        BatchCollector.submit(bc, :fast, :item, fn items -> {:ok, items} end, max_batch_size: 1)
      end)

    assert result == {:ok, [:item]}
    assert elapsed < 200_000

    Task.await(slow_task, 5_000)
  end