  test "an omitted :reset defaults to :detect while other options are explicit" do
    # The pair 100 -> 40 decreases, so reset detection attributes the later
    # value 40 to bucket 0; :raw would have attributed -60 instead.
    data = [{0, 100}, {300, 40}]
    result = CounterResampler.resample(data, @interval, mode: :delta, fill: :zero)

    assert result == [{0, 40}]
  end