  test "store and retrieve binary content with null bytes", %{store: s} do
    content = <<0, 1, 2, 255, 254, 253>>
    {:ok, hash} = ObjectStore.store(s, content)
    assert {:ok, ^content} = ObjectStore.retrieve(s, hash)
  end