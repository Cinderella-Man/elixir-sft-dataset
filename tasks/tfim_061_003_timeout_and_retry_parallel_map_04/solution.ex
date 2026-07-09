  test "order preserved when tasks finish out of order" do
    results =
      RetryMap.pmap(
        1..6,
        fn x ->
          Process.sleep((7 - x) * 20)
          x
        end,
        max_concurrency: 6,
        timeout: 1000
      )

    assert results == Enum.map(1..6, &{:ok, &1})
  end