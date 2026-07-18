  test "a timestamp exactly on a boundary opens the next bucket" do
    # 1999 -> bucket 0, 2000 -> bucket 2000 (not 0), and the joint max at
    # exactly 4000 must still produce bucket 4000 as the last row.
    series = %{cpu: [{1_999, 2}, {2_000, 1}], mem: [{4_000, 3}]}
    result = MultiSeriesResampler.resample(series, @interval, agg: :sum, fill: nil)

    assert result == [
             {0, %{cpu: 2, mem: nil}},
             {2_000, %{cpu: 1, mem: nil}},
             {4_000, %{cpu: nil, mem: 3}}
           ]
  end