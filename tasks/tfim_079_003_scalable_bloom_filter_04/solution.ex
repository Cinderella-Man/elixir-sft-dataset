  test "small workloads do not grow past the first slice" do
    filter = ScalableBloomFilter.new(1_000, 0.01)

    filter =
      Enum.reduce(1..50, filter, fn i, f ->
        ScalableBloomFilter.add(f, "x-#{i}")
      end)

    assert ScalableBloomFilter.num_slices(filter) == 1
  end