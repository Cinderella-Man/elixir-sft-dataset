  test "store returns the SHA-1 hash of the content", %{store: s} do
    content = "hello world"
    {:ok, hash} = ObjectStore.store(s, content)

    assert hash == sha1(content)
    assert byte_size(hash) == 40
    assert hash =~ ~r/^[0-9a-f]{40}$/
  end