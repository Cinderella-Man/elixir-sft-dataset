  test "search with prefix that matches nothing returns empty list" do
    t = RadixTrie.new() |> RadixTrie.insert("hello")
    assert RadixTrie.search(t, "xyz") == []
    assert RadixTrie.search(t, "help") == []
  end