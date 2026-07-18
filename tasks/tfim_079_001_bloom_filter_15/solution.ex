  test "new/2 floors k at 1 for a very loose false-positive rate" do
    filter = BloomFilter.new(1_000, 0.9)

    assert filter.m == 220
    assert filter.k == 1
    assert Enum.all?(Tuple.to_list(filter.bits), &(&1 == 0))
    refute BloomFilter.member?(filter, "ghost")
  end