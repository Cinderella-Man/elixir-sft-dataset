  test "store returns the lowercase SHA-1 hash of the content", %{store: s} do
    {:ok, hash} = ObjectStore.store(s, "hello world")
    assert hash == sha1("hello world")
    assert byte_size(hash) == 40
    assert hash =~ ~r/^[0-9a-f]{40}$/
  end