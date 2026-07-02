  test "member?/2 always returns true for added items (no false negatives)" do
    filter = BloomFilter.new(500, 0.01)

    items = for i <- 1..500, do: "item-#{i}"
    filter = Enum.reduce(items, filter, &BloomFilter.add(&2, &1))

    for item <- items do
      assert BloomFilter.member?(filter, item),
             "Expected #{inspect(item)} to be a member but got false"
    end
  end