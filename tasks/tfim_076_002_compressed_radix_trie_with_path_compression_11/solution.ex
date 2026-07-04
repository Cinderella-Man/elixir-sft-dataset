  test "search with empty prefix returns all words sorted" do
    t =
      RadixTrie.new()
      |> RadixTrie.insert("banana")
      |> RadixTrie.insert("apple")
      |> RadixTrie.insert("cherry")

    assert RadixTrie.search(t, "") == ["apple", "banana", "cherry"]
  end