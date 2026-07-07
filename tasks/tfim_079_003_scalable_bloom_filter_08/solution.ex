  test "count tracks distinct insertions" do
    filter = ScalableBloomFilter.new(50, 0.01)

    filter =
      Enum.reduce(1..200, filter, fn i, f ->
        ScalableBloomFilter.add(f, "d-#{i}")
      end)

    assert ScalableBloomFilter.count(filter) == 200
  end