  test "has_object? reflects presence", %{store: s} do
    {:ok, hash} = ObjectStore.store(s, "present")
    assert ObjectStore.has_object?(s, hash) == true
    assert ObjectStore.has_object?(s, sha1("absent")) == false
  end