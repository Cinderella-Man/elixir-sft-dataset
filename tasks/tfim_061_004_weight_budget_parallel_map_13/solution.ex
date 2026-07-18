  test "weight of a raising element is released so later queued work still runs" do
    results =
      WeightedMap.pmap(
        [4, 1, 1],
        fn
          4 -> raise "boom"
          x -> x * 100
        end,
        & &1,
        4
      )

    assert match?({:error, _}, Enum.at(results, 0))
    assert Enum.drop(results, 1) == [100, 100]
  end