  test "insert with default weight and member?" do
    t = AutocompleteTrie.new() |> AutocompleteTrie.insert("hello")
    assert AutocompleteTrie.member?(t, "hello") == true
    assert AutocompleteTrie.member?(t, "hell") == false
    assert AutocompleteTrie.member?(t, "helloo") == false
    assert AutocompleteTrie.member?(t, "") == false
    assert AutocompleteTrie.weight(t, "hello") == 1
  end