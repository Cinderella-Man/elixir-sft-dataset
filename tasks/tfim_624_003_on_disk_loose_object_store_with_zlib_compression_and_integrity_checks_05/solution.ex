  test "store is idempotent", %{store: s} do
    {:ok, h1} = ObjectStore.store(s, "dup")
    {:ok, h2} = ObjectStore.store(s, "dup")
    assert h1 == h2
  end