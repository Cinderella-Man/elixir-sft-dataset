  test "suggest with empty prefix ranks the whole trie" do
    t =
      AutocompleteTrie.new()
      |> AutocompleteTrie.insert("low", 1)
      |> AutocompleteTrie.insert("mid", 5)
      |> AutocompleteTrie.insert("high", 9)

    assert AutocompleteTrie.suggest(t, "", 2) == ["high", "mid"]
  end