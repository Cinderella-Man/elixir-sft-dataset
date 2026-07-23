  test ":max and :min differ from :first and :last within the same bucket" do
    # cpu's bucket-0 points in time order are 10, 90, 40: the largest (90) is
    # neither the earliest nor the latest, and the smallest (10) coincides with
    # the earliest only, so implementing :max as :last or :min as :first fails.
    maxed = MultiSeriesResampler.resample(@spread, @interval, agg: :max, fill: nil)
    minned = MultiSeriesResampler.resample(@spread, @interval, agg: :min, fill: nil)
    firsted = MultiSeriesResampler.resample(@spread, @interval, agg: :first, fill: nil)
    lasted = MultiSeriesResampler.resample(@spread, @interval, agg: :last, fill: nil)

    assert row(maxed, 0).cpu == 90
    assert row(minned, 0).cpu == 10
    assert row(firsted, 0).cpu == 10
    assert row(lasted, 0).cpu == 40

    # Bucket 2000 separates :min from :first and :max from :last as well.
    assert row(maxed, 2_000).cpu == 7
    assert row(minned, 2_000).cpu == 1
    assert row(firsted, 2_000).cpu == 3
    assert row(lasted, 2_000).cpu == 7
  end