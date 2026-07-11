  test "commit differing arguments produce differing hashes", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tree")
    {:ok, base} = ObjectStore.commit(s, t, nil, "msg", "alice")
    {:ok, other_msg} = ObjectStore.commit(s, t, nil, "different", "alice")
    {:ok, other_author} = ObjectStore.commit(s, t, nil, "msg", "bob")
    assert base != other_msg
    assert base != other_author
    assert other_msg != other_author
  end