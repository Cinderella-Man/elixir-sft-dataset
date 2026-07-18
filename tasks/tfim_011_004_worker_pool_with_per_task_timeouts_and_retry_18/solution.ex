  test "await with an unknown ref times out", %{pool: pool} do
    bogus_ref = make_ref()
    assert {:error, _} = RetryPool.await(pool, bogus_ref, 200)
  end