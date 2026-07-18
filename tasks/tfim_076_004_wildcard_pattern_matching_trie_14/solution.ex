  test "delete removes an exact word" do
    t =
      WildcardTrie.new()
      |> WildcardTrie.insert("bad")
      |> WildcardTrie.delete("bad")

    assert WildcardTrie.member?(t, "bad") == false
    assert WildcardTrie.size(t) == 0
    assert WildcardTrie.matches?(t, ".ad") == false
  end