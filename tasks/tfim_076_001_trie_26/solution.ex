  test "the empty string is a member only when inserted as a word" do
    t = Trie.new() |> Trie.insert("") |> Trie.insert("a")

    assert Trie.member?(t, "") == true
    assert Trie.size(t) == 2
    assert Trie.words(t) == ["", "a"]

    t2 = Trie.delete(t, "")
    assert Trie.member?(t2, "") == false
    assert Trie.member?(t2, "a") == true
    assert Trie.size(t2) == 1
  end