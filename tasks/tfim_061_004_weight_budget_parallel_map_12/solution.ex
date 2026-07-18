    test "tracks running total and peak" do
      {:ok, m} = WeightMeter.start_link([])
      assert WeightMeter.peak(m) == 0
      assert WeightMeter.add(m, 3) == 3
      assert WeightMeter.add(m, 4) == 7
      assert WeightMeter.sub(m, 5) == 2
      assert WeightMeter.peak(m) == 7
    end