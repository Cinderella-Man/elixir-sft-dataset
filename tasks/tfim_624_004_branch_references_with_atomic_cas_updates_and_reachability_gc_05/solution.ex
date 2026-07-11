  test "retrieve returns content or not_found", %{store: s} do
    {:ok, h} = ObjectStore.store(s, "data")
    assert {:ok, "data"} = ObjectStore.retrieve(s, h)
    assert {:error, :not_found} = ObjectStore.retrieve(s, sha1("nope"))
  end