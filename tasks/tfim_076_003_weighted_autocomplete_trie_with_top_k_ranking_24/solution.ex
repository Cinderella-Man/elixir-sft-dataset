  test "accumulated weight drives suggest ranking ahead of a heavier single insert" do
    t =
      AutocompleteTrie.new()
      |> AutocompleteTrie.insert("aa", 3)
      |> AutocompleteTrie.insert("ab", 5)
      |> AutocompleteTrie.insert("aa", 4)

    assert AutocompleteTrie.weight(t, "aa") == 7
    assert AutocompleteTrie.size(t) == 2
    assert AutocompleteTrie.suggest(t, "a", 2) == ["aa", "ab"]
  end