  test "never exceeds the weight budget" do
    {:ok, meter} = WeightMeter.start_link([])

    input = [3, 5, 2, 4, 6, 1, 3, 2]

    WeightedMap.pmap(
      input,
      fn x ->
        WeightMeter.add(meter, x)
        slow(:ok, 40)
        WeightMeter.sub(meter, x)
      end,
      & &1,
      8
    )

    assert WeightMeter.peak(meter) <= 8
  end