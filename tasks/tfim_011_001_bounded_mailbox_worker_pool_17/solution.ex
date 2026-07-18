  test "await with an unknown ref returns an error or times out", %{pool: pool} do
    bogus_ref = make_ref()
    assert {:error, _} = WorkerPool.await(pool, bogus_ref, 200)
  end