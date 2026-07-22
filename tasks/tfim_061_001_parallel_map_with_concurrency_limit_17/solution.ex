  test "an exiting function returns {:error, reason} for that item only" do
    results =
      ParallelMap.pmap(
        1..5,
        fn
          3 -> exit(:no_thanks)
          x -> slow(x * 2, 40)
        end,
        5
      )

    assert Enum.at(results, 0) == 2
    assert Enum.at(results, 1) == 4
    assert match?({:error, _}, Enum.at(results, 2))
    assert Enum.at(results, 3) == 8
    assert Enum.at(results, 4) == 10
  end