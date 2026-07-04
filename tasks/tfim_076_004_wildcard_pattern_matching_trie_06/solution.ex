  test "inserting the same word twice doesn't grow size" do
    t =
      WildcardTrie.new()
      |> WildcardTrie.insert("bad")
      |> WildcardTrie.insert("bad")

    assert WildcardTrie.size(t) == 1
  end