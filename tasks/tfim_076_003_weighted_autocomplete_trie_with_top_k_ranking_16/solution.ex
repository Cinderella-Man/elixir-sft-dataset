  test "deleting from empty trie returns empty trie" do
    t = AutocompleteTrie.new() |> AutocompleteTrie.delete("anything")
    assert AutocompleteTrie.size(t) == 0
  end