  test "retrieve returns content that was stored", %{store: s} do
    content = "some binary data \x00\x01\x02"
    {:ok, hash} = ObjectStore.store(s, content)
    assert {:ok, ^content} = ObjectStore.retrieve(s, hash)
  end