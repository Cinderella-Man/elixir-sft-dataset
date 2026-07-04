  test "inserting the same word accumulates weight without growing size" do
    t =
      AutocompleteTrie.new()
      |> AutocompleteTrie.insert("apple", 3)
      |> AutocompleteTrie.insert("apple", 5)

    assert AutocompleteTrie.weight(t, "apple") == 8
    assert AutocompleteTrie.size(t) == 1
  end