  test "retrieve returns the stored content", %{store: s} do
    {:ok, hash} = ObjectStore.store(s, "round trip")
    assert {:ok, "round trip"} = ObjectStore.retrieve(s, hash)
  end