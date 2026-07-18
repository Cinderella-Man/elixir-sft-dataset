  test "words returns all words sorted" do
    t =
      AutocompleteTrie.new()
      |> AutocompleteTrie.insert("zebra", 1)
      |> AutocompleteTrie.insert("apple", 1)
      |> AutocompleteTrie.insert("mango", 1)

    assert AutocompleteTrie.words(t) == ["apple", "mango", "zebra"]
    assert AutocompleteTrie.size(t) == 3
  end