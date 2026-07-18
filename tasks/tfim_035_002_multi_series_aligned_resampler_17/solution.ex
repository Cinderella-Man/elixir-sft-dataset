  test ":first picks per-series earliest value in the bucket" do
    # Earliest by timestamp, not smallest and not first in the input list:
    # cpu's bucket-0 points arrive out of order and its earliest value (10)
    # sits below its latest (40) and its largest (90).
    result = MultiSeriesResampler.resample(@spread, @interval, agg: :first, fill: nil)

    assert row(result, 0) == %{cpu: 10, mem: 8}
    assert row(result, 2_000) == %{cpu: 3, mem: 6}
  end