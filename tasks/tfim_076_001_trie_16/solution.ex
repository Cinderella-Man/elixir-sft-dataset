  test "deleting from empty trie returns empty trie" do
    t = Trie.new() |> Trie.delete("anything")
    assert Trie.size(t) == 0
  end