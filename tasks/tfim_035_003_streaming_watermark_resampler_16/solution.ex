  test "bucket closes at exactly the equal watermark threshold, not before" do
    {:ok, pid} = StreamingResampler.start_link(1_000, agg: :sum, allowed_lateness: 500)

    :ok = StreamingResampler.push(pid, 0, 5)
    :ok = StreamingResampler.push(pid, 1_499, 1)
    # threshold is 0 + 1000 + 500 = 1500; watermark 1499 is one ms short
    assert StreamingResampler.finalized(pid) == []

    :ok = StreamingResampler.push(pid, 1_500, 2)
    # watermark now exactly 1500 -> bucket 0 finalizes
    assert StreamingResampler.finalized(pid) == [{0, 5}]
  end