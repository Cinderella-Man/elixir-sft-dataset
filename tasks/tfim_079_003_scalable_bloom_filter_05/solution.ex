  test "member?/2 true for every added item, even after growth" do
    filter = ScalableBloomFilter.new(100, 0.01)
    items = for i <- 1..1_000, do: "member-#{i}"

    filter = Enum.reduce(items, filter, &ScalableBloomFilter.add(&2, &1))

    for item <- items do
      assert ScalableBloomFilter.member?(filter, item),
             "Expected #{inspect(item)} to be a member after growth"
    end
  end