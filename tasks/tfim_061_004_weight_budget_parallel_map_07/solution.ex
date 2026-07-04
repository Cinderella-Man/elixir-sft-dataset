  test "a task heavier than the budget runs alone" do
    {:ok, meter} = WeightMeter.start_link([])

    # weight 10 > budget 4: it must run by itself, so the peak is exactly 10.
    WeightedMap.pmap(
      [10, 1],
      fn x ->
        WeightMeter.add(meter, x)
        slow(:ok, 40)
        WeightMeter.sub(meter, x)
      end,
      & &1,
      4
    )

    assert WeightMeter.peak(meter) == 10
  end