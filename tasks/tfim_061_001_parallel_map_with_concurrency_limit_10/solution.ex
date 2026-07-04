  test "a crashing function returns {:error, reason} for that item" do
    results =
      ParallelMap.pmap(
        [1, 2, 3],
        fn
          2 -> raise "boom"
          x -> x * 10
        end,
        3
      )

    assert Enum.at(results, 0) == 10
    assert match?({:error, _}, Enum.at(results, 1))
    assert Enum.at(results, 2) == 30
  end