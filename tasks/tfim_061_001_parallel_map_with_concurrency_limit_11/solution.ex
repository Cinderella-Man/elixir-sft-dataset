  test "crash in one task does not cancel other tasks" do
    results =
      ParallelMap.pmap(
        1..5,
        fn
          3 -> raise "only me"
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