  test "size and words" do
    t =
      WildcardTrie.new()
      |> WildcardTrie.insert("mad")
      |> WildcardTrie.insert("bad")
      |> WildcardTrie.insert("dad")

    assert WildcardTrie.size(t) == 3
    assert WildcardTrie.words(t) == ["bad", "dad", "mad"]
  end