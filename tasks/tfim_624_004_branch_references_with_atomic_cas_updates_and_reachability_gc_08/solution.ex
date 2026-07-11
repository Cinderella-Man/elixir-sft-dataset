  test "commit stores a retrievable object", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tree")
    {:ok, c} = ObjectStore.commit(s, t, nil, "root", "alice")
    assert {:ok, content} = ObjectStore.retrieve(s, c)
    assert is_binary(content)
    assert c == sha1(content)
  end