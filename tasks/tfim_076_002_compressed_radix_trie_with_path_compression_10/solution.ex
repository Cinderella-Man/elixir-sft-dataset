  test "search where prefix ends in the middle of a compressed edge" do
    t =
      RadixTrie.new()
      |> RadixTrie.insert("car")
      |> RadixTrie.insert("card")
      |> RadixTrie.insert("cat")

    # "ca" is not a stored word, but a stored edge is "ca"
    assert RadixTrie.member?(t, "ca") == false
    assert RadixTrie.search(t, "ca") == ["car", "card", "cat"]
    assert RadixTrie.search(t, "c") == ["car", "card", "cat"]
  end