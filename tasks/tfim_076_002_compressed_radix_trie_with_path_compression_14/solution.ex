  test "words returns all inserted words sorted" do
    t =
      RadixTrie.new()
      |> RadixTrie.insert("zebra")
      |> RadixTrie.insert("apple")
      |> RadixTrie.insert("mango")
      |> RadixTrie.insert("apricot")

    assert RadixTrie.words(t) == ["apple", "apricot", "mango", "zebra"]
  end