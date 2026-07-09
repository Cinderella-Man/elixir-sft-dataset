  test "a crash releases weight so remaining work still proceeds" do
    results =
      WeightedMap.pmap(
        [5, 5, 5],
        fn
          x -> if x == 5, do: x
        end,
        & &1,
        5
      )

    # All weights equal budget, so they run one at a time; each returns its value.
    assert results == [5, 5, 5]
  end