  test "size tracks inserted words" do
    t =
      RadixTrie.new()
      |> RadixTrie.insert("a")
      |> RadixTrie.insert("ab")
      |> RadixTrie.insert("abc")

    assert RadixTrie.size(t) == 3
  end