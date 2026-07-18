  test "crashed task frees its slot for queued callers" do
    {:ok, kp} = KeyedPool.start_link(max_concurrency: 1)

    # First task crashes
    task1 =
      Task.async(fn ->
        KeyedPool.execute(kp, :crash, fn -> raise "boom" end)
      end)

    Process.sleep(30)

    # Second task should get the slot after the crash
    task2 =
      Task.async(fn ->
        KeyedPool.execute(kp, :crash, fn -> {:ok, :recovered} end)
      end)

    result1 = Task.await(task1, 5_000)
    result2 = Task.await(task2, 5_000)

    assert {:error, {:exception, %RuntimeError{message: "boom"}}} = result1
    assert result2 == {:ok, :recovered}
  end