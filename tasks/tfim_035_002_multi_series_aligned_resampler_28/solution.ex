  test "both options omitted use :last aggregation and nil gap filling" do
    # cpu's bucket-0 values in time order are 10, 90, 40 and bucket 2000 is
    # empty: the defaults must yield 40 there and leave the gap nil.
    series = %{cpu: [{1_500, 40}, {0, 10}, {500, 90}, {4_200, 7}]}
    result = MultiSeriesResampler.resample(series, @interval, [])

    assert result == [{0, %{cpu: 40}}, {2_000, %{cpu: nil}}, {4_000, %{cpu: 7}}]
  end