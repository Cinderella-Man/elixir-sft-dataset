  test "filter grows new slices as capacity is exceeded" do
    filter = ScalableBloomFilter.new(100, 0.01)

    filter =
      Enum.reduce(1..500, filter, fn i, f ->
        ScalableBloomFilter.add(f, "item-#{i}")
      end)

    assert ScalableBloomFilter.num_slices(filter) > 1,
           "expected the filter to have grown beyond one slice"
  end