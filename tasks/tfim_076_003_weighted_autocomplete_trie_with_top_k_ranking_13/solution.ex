  test "delete removes a word entirely" do
    t =
      AutocompleteTrie.new()
      |> AutocompleteTrie.insert("hello", 7)
      |> AutocompleteTrie.delete("hello")

    assert AutocompleteTrie.member?(t, "hello") == false
    assert AutocompleteTrie.weight(t, "hello") == 0
    assert AutocompleteTrie.size(t) == 0
  end