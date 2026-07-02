  test "submit and await a simple task", %{pool: pool} do
    {:ok, ref} = RetryPool.submit(pool, quick_task(42))
    assert {:ok, 42} = RetryPool.await(pool, ref, 1_000)
  end