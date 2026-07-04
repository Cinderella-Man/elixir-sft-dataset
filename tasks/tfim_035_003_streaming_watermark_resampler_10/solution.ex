  test "finalized/flush/stats before any push" do
    {:ok, pid} = StreamingResampler.start_link(1_000, agg: :sum)

    assert StreamingResampler.finalized(pid) == []
    assert StreamingResampler.flush(pid) == []
    assert StreamingResampler.stats(pid).watermark == nil
  end