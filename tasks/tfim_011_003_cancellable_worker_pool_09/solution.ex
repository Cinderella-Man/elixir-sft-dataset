  test "cancel an already-completed task returns not_found", %{pool: pool} do
    {:ok, ref} = CancellablePool.submit(pool, quick_task(:done))
    assert {:ok, :done} = CancellablePool.await(pool, ref, 1_000)

    # Try to cancel after completion
    assert {:error, :not_found} = CancellablePool.cancel(pool, ref)
  end