  test "with no options the defaults are :delta, :detect and :zero" do
    # Samples exercising all three defaults at once:
    #   t=0    v=100   first sample, no predecessor
    #   t=300  v=150   (+50, bucket 0)
    #   t=1000..1999   no sample -> empty bucket, must fill (not nil)
    #   t=2300 v=400   (+250, bucket 2000)
    #   t=2800 v=50    decrease -> reset detection gives +50 (raw would give -350)
    data = [{0, 100}, {300, 150}, {2_300, 400}, {2_800, 50}]
    result = CounterResampler.resample(data, @interval, [])

    # Strict comparison: :rate would emit floats, :raw would make bucket 2000
    # -100, and fill: nil would make bucket 1000 nil.
    assert result === [{0, 50}, {1_000, 0}, {2_000, 300}]
  end