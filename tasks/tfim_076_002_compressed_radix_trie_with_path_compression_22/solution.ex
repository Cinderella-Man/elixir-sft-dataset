  test "larger dataset — 100 words" do
    words = for i <- 1..100, do: "word#{String.pad_leading("#{i}", 3, "0")}"

    t = Enum.reduce(words, RadixTrie.new(), &RadixTrie.insert(&2, &1))

    assert RadixTrie.size(t) == 100
    assert RadixTrie.member?(t, "word001") == true
    assert RadixTrie.member?(t, "word100") == true
    assert RadixTrie.member?(t, "word101") == false

    results = RadixTrie.search(t, "word0")
    assert length(results) == 99

    assert RadixTrie.words(t) == Enum.sort(words)
    # compression: far fewer nodes than the ~700 characters stored
    assert RadixTrie.node_count(t) < 200
  end