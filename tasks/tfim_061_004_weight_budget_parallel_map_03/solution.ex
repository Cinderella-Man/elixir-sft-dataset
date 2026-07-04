  test "returns results in original order" do
    input = Enum.to_list(1..10)
    results = WeightedMap.pmap(input, fn x -> x * 10 end, fn _ -> 1 end, 3)
    assert results == Enum.map(input, &(&1 * 10))
  end