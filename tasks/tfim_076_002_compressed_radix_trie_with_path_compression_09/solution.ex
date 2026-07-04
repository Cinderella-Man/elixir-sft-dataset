  test "search returns all words with the given prefix, sorted" do
    t =
      RadixTrie.new()
      |> RadixTrie.insert("car")
      |> RadixTrie.insert("card")
      |> RadixTrie.insert("care")
      |> RadixTrie.insert("careful")
      |> RadixTrie.insert("cat")
      |> RadixTrie.insert("dog")

    assert RadixTrie.search(t, "car") == ["car", "card", "care", "careful"]
    assert RadixTrie.search(t, "care") == ["care", "careful"]
    assert RadixTrie.search(t, "cat") == ["cat"]
    assert RadixTrie.search(t, "d") == ["dog"]
  end