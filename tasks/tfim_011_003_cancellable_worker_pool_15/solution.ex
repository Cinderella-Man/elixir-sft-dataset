  test "pool remains functional after a worker crash", %{pool: pool} do
    {:ok, ref_crash} = CancellablePool.submit(pool, fn -> raise "kaboom" end)
    CancellablePool.await(pool, ref_crash, 2_000)

    Process.sleep(100)

    {:ok, ref} = CancellablePool.submit(pool, quick_task(:after_crash))
    assert {:ok, :after_crash} = CancellablePool.await(pool, ref, 1_000)
  end