  test "merge/2 clamps summed counters at 255" do
    build = fn item ->
      Enum.reduce(1..200, CountingBloomFilter.new(50, 0.01), fn _i, f ->
        CountingBloomFilter.add(f, item)
      end)
    end

    f1 = build.("shared")
    f2 = build.("shared")

    merged = CountingBloomFilter.merge(f1, f2)
    counters = Tuple.to_list(merged.counters)

    # Element-wise sums would reach 400 for the shared slots; they must clamp.
    assert Enum.all?(counters, fn c -> c <= 255 end)
    assert Enum.max(counters) == 255
    assert CountingBloomFilter.member?(merged, "shared")
    assert CountingBloomFilter.count(merged) == 400
  end