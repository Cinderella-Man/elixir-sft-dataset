  test "delete on a missing key returns :ok", %{c: c} do
    assert :ok = SwrCache.delete(c, :never_existed)
    assert :miss = SwrCache.get(c, :never_existed)
  end