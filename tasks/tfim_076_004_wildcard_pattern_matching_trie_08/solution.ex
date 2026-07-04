  test "matches? respects length exactly" do
    t = WildcardTrie.new() |> WildcardTrie.insert("bad")

    assert WildcardTrie.matches?(t, "..") == false
    assert WildcardTrie.matches?(t, "....") == false
    assert WildcardTrie.matches?(t, "...") == true
  end