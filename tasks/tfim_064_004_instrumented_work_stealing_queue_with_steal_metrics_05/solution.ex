  test "single worker performs no steals" do
    items = Enum.to_list(1..10)
    %{metrics: metrics} = WorkStealQueue.run(items, 1, fn x -> x + 1 end)

    assert metrics.steals == %{0 => 0}
    assert metrics.stolen == %{0 => 0}
    assert metrics.processed == %{0 => 10}
  end