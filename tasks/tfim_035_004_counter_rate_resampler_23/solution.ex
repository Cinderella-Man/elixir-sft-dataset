  test "an omitted :fill defaults to :zero while other options are explicit" do
    # Bucket 1000 receives no increment; the default fill makes it 0, not nil.
    data = [{0, 100}, {300, 150}, {2_300, 400}]
    result = CounterResampler.resample(data, @interval, mode: :delta, reset: :detect)

    assert result === [{0, 50}, {1_000, 0}, {2_000, 250}]
  end