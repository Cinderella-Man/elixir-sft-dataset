  test "invalidate_all on an unused table returns :ok without error", %{cl: cl} do
    assert :ok = CacheLayer.invalidate_all(cl, :never_used_table)
  end