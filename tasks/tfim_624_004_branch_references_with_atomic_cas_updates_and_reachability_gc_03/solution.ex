  test "store keeps distinct content under distinct hashes", %{store: s} do
    {:ok, ha} = ObjectStore.store(s, "alpha")
    {:ok, hb} = ObjectStore.store(s, "beta")
    assert ha != hb
    assert {:ok, "alpha"} = ObjectStore.retrieve(s, ha)
    assert {:ok, "beta"} = ObjectStore.retrieve(s, hb)
  end