  test "raise, exit and kill failures coexist in one call" do
    results =
      ParallelMap.pmap(
        [:raise, :ok_a, :exit, :ok_b, :kill],
        fn
          :raise -> raise "nope"
          :exit -> exit(:bye)
          :kill -> Process.exit(self(), :kill)
          other -> slow(other, 30)
        end,
        3
      )

    assert match?({:error, _}, Enum.at(results, 0))
    assert Enum.at(results, 1) == :ok_a
    assert match?({:error, _}, Enum.at(results, 2))
    assert Enum.at(results, 3) == :ok_b
    assert match?({:error, _}, Enum.at(results, 4))
  end