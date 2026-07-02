  test "returns results in original order" do
    input = Enum.to_list(1..20)

    results = ParallelMap.pmap(input, fn x -> x * 10 end, 4)

    assert results == Enum.map(input, &(&1 * 10))
  end