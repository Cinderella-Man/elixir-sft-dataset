  test "GenServer is not blocked while tasks are running", %{kp: kp} do
    slow =
      Task.async(fn ->
        KeyedPool.execute(kp, :slow, fn ->
          Process.sleep(500)
          {:ok, :slow}
        end)
      end)

    Process.sleep(30)

    {elapsed, result} =
      :timer.tc(fn ->
        KeyedPool.execute(kp, :fast, fn -> {:ok, :fast} end)
      end)

    assert result == {:ok, :fast}
    assert elapsed < 200_000

    Task.await(slow, 5_000)
  end