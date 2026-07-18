  test "omitting :agg aggregates with :last" do
    # cpu's bucket values in time order are 10, 90, 40, so :last (40) differs
    # from :first, :min, :max, :sum, :count and :mean.
    series = %{cpu: [{1_500, 40}, {0, 10}, {500, 90}], mem: [{200, 3}, {900, 8}]}
    result = MultiSeriesResampler.resample(series, @interval, fill: nil)

    assert result == [{0, %{cpu: 40, mem: 8}}]
  end