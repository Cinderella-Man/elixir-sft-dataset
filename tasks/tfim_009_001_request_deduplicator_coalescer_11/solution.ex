  test "GenServer is not blocked while a function is running", %{dd: dd} do
    # Start a slow execution on key "slow"
    slow_task =
      Task.async(fn ->
        Dedup.execute(dd, "slow", fn ->
          Process.sleep(500)
          {:ok, :slow_result}
        end)
      end)

    # Give it a moment to start
    Process.sleep(50)

    # A call on a different key should return quickly, not block
    {elapsed, result} =
      :timer.tc(fn ->
        Dedup.execute(dd, "fast", fn -> {:ok, :fast_result} end)
      end)

    assert result == {:ok, :fast_result}
    # Should be well under 500ms — the GenServer isn't blocked
    # microseconds
    assert elapsed < 200_000

    # Clean up
    Task.await(slow_task, 5_000)
  end