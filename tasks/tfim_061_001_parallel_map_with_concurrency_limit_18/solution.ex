  test "a brutally killed task returns {:error, reason} without cancelling others" do
    results =
      ParallelMap.pmap(
        1..4,
        fn
          2 -> Process.exit(self(), :kill)
          x -> slow(x * 3, 40)
        end,
        4
      )

    assert Enum.at(results, 0) == 3
    assert match?({:error, _}, Enum.at(results, 1))
    assert Enum.at(results, 2) == 9
    assert Enum.at(results, 3) == 12
  end