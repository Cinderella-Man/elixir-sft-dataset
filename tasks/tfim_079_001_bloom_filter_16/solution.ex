  test "add/2 sets exactly the bits phash2({i, item}, m) for i in 0..k-1" do
    filter = BloomFilter.new(1_000, 0.01)

    for item <- ["probe-a", :probe_b, 12_345, {:probe, "c"}, [1, 2, 3]] do
      added = BloomFilter.add(filter, item)
      expected = MapSet.new(hash_indices(filter, item))

      assert set_bit_indices(added.bits) == expected
      assert tuple_size(added.bits) == tuple_size(filter.bits)
      assert added.m == filter.m
      assert added.k == filter.k
    end
  end