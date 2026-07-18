  test "result order is preserved even when tasks finish out of order" do
    # Items with larger index sleep longer, so they finish last
    input = Enum.to_list(1..6)

    results =
      ParallelMap.pmap(
        input,
        fn x ->
          # item 1 sleeps longest
          Process.sleep((7 - x) * 20)
          x
        end,
        6
      )

    assert results == input
  end