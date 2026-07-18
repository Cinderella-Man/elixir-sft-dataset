  test "member?/2 needs every one of the k bits, first and last seed included" do
    filter = BloomFilter.new(1_000, 0.01)

    # Pick a probe whose k bit indices are all distinct, so that dropping any
    # single one of them really leaves that bit unset.
    item =
      Enum.find(Enum.map(0..99, &"seed-probe-#{&1}"), fn candidate ->
        indices = hash_indices(filter, candidate)
        length(Enum.uniq(indices)) == filter.k
      end)

    assert item
    indices = hash_indices(filter, item)

    full = %BloomFilter{filter | bits: bits_from_indices(indices, filter.m)}
    assert BloomFilter.member?(full, item)

    for dropped <- [List.first(indices), List.last(indices)] do
      remaining = indices -- [dropped]
      partial = %BloomFilter{filter | bits: bits_from_indices(remaining, filter.m)}

      refute BloomFilter.member?(partial, item)
    end
  end