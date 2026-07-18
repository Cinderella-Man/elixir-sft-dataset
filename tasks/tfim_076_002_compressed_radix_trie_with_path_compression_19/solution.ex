  test "deleting from empty trie returns empty trie" do
    t = RadixTrie.new() |> RadixTrie.delete("anything")
    assert RadixTrie.size(t) == 0
  end