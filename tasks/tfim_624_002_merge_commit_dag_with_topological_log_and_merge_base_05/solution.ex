  test "storing the same content twice returns the same hash", %{store: s} do
    {:ok, h1} = ObjectStore.store(s, "duplicate")
    {:ok, h2} = ObjectStore.store(s, "duplicate")
    assert h1 == h2
  end