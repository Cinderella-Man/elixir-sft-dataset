  test "a task killed abnormally yields an error tuple and leaves the others intact" do
    results =
      WeightedMap.pmap(
        [1, 2, 3],
        fn
          2 -> Process.exit(self(), :kill)
          x -> x * 10
        end,
        fn _ -> 1 end,
        3
      )

    assert Enum.at(results, 0) == 10
    assert Enum.at(results, 1) == {:error, :killed}
    assert Enum.at(results, 2) == 30
  end