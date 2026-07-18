  test "words that are prefixes of each other" do
    t =
      Trie.new()
      |> Trie.insert("a")
      |> Trie.insert("ab")
      |> Trie.insert("abc")
      |> Trie.insert("abcd")

    assert Trie.size(t) == 4
    assert Trie.search(t, "ab") == ["ab", "abc", "abcd"]

    t2 = Trie.delete(t, "ab")
    assert Trie.member?(t2, "ab") == false
    assert Trie.member?(t2, "abc") == true
    assert Trie.search(t2, "ab") == ["abc", "abcd"]
  end