  test "invalidate_all on an unused table returns :ok" do
    cl = start_cache([])
    assert :ok = CacheLayer.invalidate_all(cl, :never_used)
  end