  test "store and retrieve empty content", %{store: s} do
    {:ok, hash} = ObjectStore.store(s, "")
    assert {:ok, ""} = ObjectStore.retrieve(s, hash)
    assert hash == sha1("")
  end