  test "deleting a non-existent word changes nothing" do
    t = AutocompleteTrie.new() |> AutocompleteTrie.insert("hello", 1)
    t2 = AutocompleteTrie.delete(t, "world")

    assert AutocompleteTrie.member?(t2, "hello") == true
    assert AutocompleteTrie.size(t2) == 1
  end