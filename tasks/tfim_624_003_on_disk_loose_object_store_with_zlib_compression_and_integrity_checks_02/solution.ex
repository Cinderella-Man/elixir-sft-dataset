  test "store returns the lowercase SHA-1 hash", %{store: s} do
    {:ok, hash} = ObjectStore.store(s, "hello world")
    assert hash == sha1("hello world")
    assert hash =~ ~r/^[0-9a-f]{40}$/
  end