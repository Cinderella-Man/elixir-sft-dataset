  test "await with an unknown ref returns timeout", %{pool: pool} do
    bogus_ref = make_ref()
    assert {:error, _} = CancellablePool.await(pool, bogus_ref, 200)
  end