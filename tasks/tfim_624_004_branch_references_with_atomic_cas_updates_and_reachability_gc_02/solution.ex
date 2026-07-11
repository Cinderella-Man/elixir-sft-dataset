  test "store returns lowercase SHA-1 and is idempotent", %{store: s} do
    {:ok, h1} = ObjectStore.store(s, "hi")
    {:ok, h2} = ObjectStore.store(s, "hi")
    assert h1 == sha1("hi")
    assert h1 == h2
  end