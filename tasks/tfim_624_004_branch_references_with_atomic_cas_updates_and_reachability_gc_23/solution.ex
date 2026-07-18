  test "gc on an empty store removes nothing", %{store: s} do
    assert {:ok, 0} = ObjectStore.gc(s)
  end