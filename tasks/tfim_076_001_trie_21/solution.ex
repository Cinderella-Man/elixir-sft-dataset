  test "larger dataset — 100 words" do
    words = for i <- 1..100, do: "word#{String.pad_leading("#{i}", 3, "0")}"

    t = Enum.reduce(words, Trie.new(), &Trie.insert(&2, &1))

    assert Trie.size(t) == 100
    assert Trie.member?(t, "word001") == true
    assert Trie.member?(t, "word100") == true
    assert Trie.member?(t, "word101") == false

    # Prefix search for "word0" should return word001..word099
    results = Trie.search(t, "word0")
    assert length(results) == 99

    # All words sorted
    all = Trie.words(t)
    assert all == Enum.sort(words)
  end