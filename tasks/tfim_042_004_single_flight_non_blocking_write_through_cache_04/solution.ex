  test "nil is a valid cached value and is not recomputed", %{cl: cl} do
    fun = fn -> nil end
    assert {:ok, nil} = CacheLayer.fetch(cl, :t, "k", fun)
    assert {:ok, nil} = CacheLayer.fetch(cl, :t, "k", fun)
  end