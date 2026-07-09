  test "order preserved when tasks finish out of order" do
    results =
      WeightedMap.pmap(
        1..6,
        fn x ->
          Process.sleep((7 - x) * 20)
          x
        end,
        fn _ -> 1 end,
        6
      )

    assert results == Enum.to_list(1..6)
  end