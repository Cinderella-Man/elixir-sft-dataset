  test "each live entry holds a unique recency stamp that grows with insertion order" do
    c = start_cache(4)
    data = :"#{c}_data"

    for k <- [:a, :b, :c, :d], do: LFUCache.put(c, k, k)

    stamps =
      for k <- [:a, :b, :c, :d] do
        assert [{^k, {^k, 1, seq}}] = :ets.lookup(data, k)
        assert is_integer(seq)
        seq
      end

    # no two live entries share a stamp, and every insert drew a larger one
    assert length(Enum.uniq(stamps)) == 4
    assert stamps == Enum.sort(stamps)
  end