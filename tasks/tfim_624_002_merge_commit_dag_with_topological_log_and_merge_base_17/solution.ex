  test "the stored commit object is a text representation carrying every field", %{store: s} do
    {:ok, t} = ObjectStore.store(s, "tree-content")
    {:ok, c} = ObjectStore.commit(s, t, [], "an important message", "alice")
    {:ok, raw} = ObjectStore.retrieve(s, c)

    assert String.printable?(raw)
    assert raw =~ t
    assert raw =~ "an important message"
    assert raw =~ "alice"
  end