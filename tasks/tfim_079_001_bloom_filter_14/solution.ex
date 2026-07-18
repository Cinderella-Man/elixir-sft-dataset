  test "new/2 derives the documented m, k, word count and all-zero words" do
    filter = BloomFilter.new(1_000, 0.01)

    assert filter.m == 9586
    assert filter.k == 7
    # ceil(m / 64) 64-bit words
    assert tuple_size(filter.bits) == 150
    assert Enum.all?(Tuple.to_list(filter.bits), &(&1 == 0))
  end