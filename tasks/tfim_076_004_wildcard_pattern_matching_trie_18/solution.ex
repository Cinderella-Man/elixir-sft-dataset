  test "deleting from empty trie returns empty trie" do
    t = WildcardTrie.new() |> WildcardTrie.delete("anything")
    assert WildcardTrie.size(t) == 0
  end