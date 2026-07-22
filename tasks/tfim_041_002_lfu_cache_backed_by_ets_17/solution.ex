  test "a data row is {key, {value, frequency, seq}} with the triple nested, not flattened" do
    c = start_cache(3)
    data = :"#{c}_data"

    # a brand-new entry is stored at frequency 1 alongside its recency stamp
    LFUCache.put(c, :a, :v1)
    assert [{:a, {:v1, 1, seq1}}] = :ets.lookup(data, :a)
    assert is_integer(seq1)

    # a hit raises the frequency in place and draws a strictly larger stamp
    assert {:ok, :v1} = LFUCache.get(c, :a)
    assert [{:a, {:v1, 2, seq2}}] = :ets.lookup(data, :a)
    assert is_integer(seq2)
    assert seq2 > seq1

    # an update rewrites the value inside the same nested triple
    LFUCache.put(c, :a, :v2)
    assert [{:a, {:v2, 3, seq3}}] = :ets.lookup(data, :a)
    assert is_integer(seq3)
    assert seq3 > seq2
  end