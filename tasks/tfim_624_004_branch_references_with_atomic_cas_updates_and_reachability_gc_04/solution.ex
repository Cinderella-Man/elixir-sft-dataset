  test "store handles binary content with null bytes", %{store: s} do
    payload = <<0, 1, 2, 255, 0>>
    {:ok, h} = ObjectStore.store(s, payload)
    assert h == sha1(payload)
    assert {:ok, ^payload} = ObjectStore.retrieve(s, h)
  end