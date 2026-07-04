  test "runs several small tasks in parallel under the budget" do
    {:ok, meter} = WeightMeter.start_link([])

    WeightedMap.pmap(
      List.duplicate(1, 6),
      fn x ->
        WeightMeter.add(meter, x)
        slow(:ok, 80)
        WeightMeter.sub(meter, x)
      end,
      & &1,
      3
    )

    assert WeightMeter.peak(meter) >= 2
    assert WeightMeter.peak(meter) <= 3
  end