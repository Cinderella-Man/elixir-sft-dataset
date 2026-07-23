  test "an omitted :mode defaults to :delta while other options are explicit" do
    # Increments +50 and +50 both land in bucket 0.  Under :delta the bucket is
    # the integer 50 + 50 = 100; under :rate it would be the float 100.0, so the
    # strict comparison discriminates the two modes.
    data = [{0, 100}, {300, 150}, {700, 200}]
    result = CounterResampler.resample(data, @interval, reset: :detect, fill: :zero)

    assert result === [{0, 100}]
  end