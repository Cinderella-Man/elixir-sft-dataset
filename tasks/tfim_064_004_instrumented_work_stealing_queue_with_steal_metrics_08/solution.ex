  test "empty item list returns empty results and zeroed metrics" do
    %{results: results, metrics: metrics} = WorkStealQueue.run([], 3, fn x -> x end)

    assert results == []
    assert metrics.processed == %{0 => 0, 1 => 0, 2 => 0}
    assert metrics.steals == %{0 => 0, 1 => 0, 2 => 0}
    assert metrics.stolen == %{0 => 0, 1 => 0, 2 => 0}
  end