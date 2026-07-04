  test "cancel an unknown ref returns not_found", %{pool: pool} do
    bogus_ref = make_ref()
    assert {:error, :not_found} = CancellablePool.cancel(pool, bogus_ref)
  end