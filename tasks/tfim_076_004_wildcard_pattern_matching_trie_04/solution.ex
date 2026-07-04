  test "member? does not interpret dots as wildcards" do
    t =
      WildcardTrie.new()
      |> WildcardTrie.insert("bad")
      |> WildcardTrie.insert("dad")

    # "." here is a literal, so no stored word equals "bad" via wildcard
    assert WildcardTrie.member?(t, ".ad") == false
    assert WildcardTrie.member?(t, "bad") == true
  end