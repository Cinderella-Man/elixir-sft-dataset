  test "adding a duplicate does not change count or grow the filter" do
    filter =
      ScalableBloomFilter.new(100, 0.01)
      |> ScalableBloomFilter.add("dup")

    slices_before = ScalableBloomFilter.num_slices(filter)
    filter = ScalableBloomFilter.add(filter, "dup")

    assert ScalableBloomFilter.count(filter) == 1
    assert ScalableBloomFilter.num_slices(filter) == slices_before
  end