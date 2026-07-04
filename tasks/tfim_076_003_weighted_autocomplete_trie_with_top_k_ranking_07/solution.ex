  test "suggest ranks by descending weight then lexicographically" do
    t =
      AutocompleteTrie.new()
      |> AutocompleteTrie.insert("apple", 5)
      |> AutocompleteTrie.insert("app", 3)
      |> AutocompleteTrie.insert("apply", 5)
      |> AutocompleteTrie.insert("apricot", 2)
      |> AutocompleteTrie.insert("banana", 10)

    # among "ap*": apple(5), apply(5), app(3), apricot(2)
    assert AutocompleteTrie.suggest(t, "ap", 3) == ["apple", "apply", "app"]
    assert AutocompleteTrie.suggest(t, "ap", 10) == ["apple", "apply", "app", "apricot"]
  end