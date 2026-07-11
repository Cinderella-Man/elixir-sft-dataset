  test "different content produces different hashes", %{store: s} do
    {:ok, h1} = ObjectStore.store(s, "aaa")
    {:ok, h2} = ObjectStore.store(s, "bbb")

    assert h1 != h2
  end