  test "every row's value map contains every series name" do
    result = MultiSeriesResampler.resample(@series, @interval, agg: :sum, fill: :nil)

    Enum.each(result, fn {_b, map} ->
      assert Map.has_key?(map, :cpu)
      assert Map.has_key?(map, :mem)
    end)
  end