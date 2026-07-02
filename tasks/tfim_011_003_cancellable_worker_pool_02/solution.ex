  test "submit and await a simple task", %{pool: pool} do
    {:ok, ref} = CancellablePool.submit(pool, quick_task(42))
    assert {:ok, 42} = CancellablePool.await(pool, ref, 1_000)
  end