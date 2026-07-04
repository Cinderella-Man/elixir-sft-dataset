  test "weighted elements are mapped in order" do
    input = [3, 5, 2, 4, 6, 1]
    results = WeightedMap.pmap(input, fn x -> x * 10 end, & &1, 8)
    assert results == Enum.map(input, &(&1 * 10))
  end