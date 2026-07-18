  test "the process registers under the default name when none is given" do
    start_server([])

    assert is_pid(Process.whereis(RankPercentile))
    assert :ok = RankPercentile.record(:n, 1)
    assert {:ok, 1} = RankPercentile.query(:n, 0.5)
  end