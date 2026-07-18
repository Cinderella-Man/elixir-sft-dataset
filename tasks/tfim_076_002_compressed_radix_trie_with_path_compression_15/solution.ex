  test "delete removes a word" do
    t =
      RadixTrie.new()
      |> RadixTrie.insert("hello")
      |> RadixTrie.delete("hello")

    assert RadixTrie.member?(t, "hello") == false
    assert RadixTrie.size(t) == 0
  end