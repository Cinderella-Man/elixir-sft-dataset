  test "status returns :idle during first attempt", %{rd: rd} do
    task =
      Task.async(fn ->
        RetryDedup.execute(rd, "running", fn ->
          Process.sleep(300)
          {:ok, :done}
        end)
      end)

    Process.sleep(50)
    # During initial execution (attempt 0), status is :idle (no retries yet)
    assert RetryDedup.status(rd, "running") == :idle

    Task.await(task, 5_000)
  end