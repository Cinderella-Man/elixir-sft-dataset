  test "await returns timeout when task takes too long", %{pool: pool} do
    {:ok, ref} = CancellablePool.submit(pool, slow_task(2_000, :late))
    assert {:error, :timeout} = CancellablePool.await(pool, ref, 100)
  end