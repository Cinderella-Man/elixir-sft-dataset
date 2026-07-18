  test "larger dataset — wildcard queries over 100 words" do
    words = for i <- 1..100, do: "w#{String.pad_leading("#{i}", 3, "0")}"

    t = Enum.reduce(words, WildcardTrie.new(), &WildcardTrie.insert(&2, &1))

    assert WildcardTrie.size(t) == 100
    # every word has form "w" + 3 digits => "w..." matches all
    assert length(WildcardTrie.matching(t, "w...")) == 100
    # "w00." matches w001..w009
    assert WildcardTrie.matching(t, "w00.") ==
             for(i <- 1..9, do: "w00#{i}")

    assert WildcardTrie.matches?(t, "w050") == true
    assert WildcardTrie.matches?(t, "w101") == false
    assert WildcardTrie.words(t) == Enum.sort(words)
  end