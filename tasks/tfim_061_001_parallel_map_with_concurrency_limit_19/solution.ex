  test "queued items still run after earlier tasks exit abnormally" do
    input = Enum.to_list(1..8)

    results =
      ParallelMap.pmap(
        input,
        fn
          x when x in [1, 2] -> exit({:bad, x})
          x -> slow(x * 100, 20)
        end,
        2
      )

    assert length(results) == 8
    assert match?({:error, _}, Enum.at(results, 0))
    assert match?({:error, _}, Enum.at(results, 1))
    assert Enum.drop(results, 2) == Enum.map(3..8, &(&1 * 100))
  end