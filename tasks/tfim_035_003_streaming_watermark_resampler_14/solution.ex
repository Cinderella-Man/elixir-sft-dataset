  test "agg defaults to :last when the option is omitted" do
    {:ok, pid} = StreamingResampler.start_link(1_000)

    :ok = StreamingResampler.push(pid, 100, 1)
    :ok = StreamingResampler.push(pid, 900, 2)

    # default :last -> latest timestamp in bucket 0 is 900 -> value 2 (not sum 3, not first 1)
    assert StreamingResampler.flush(pid) == [{0, 2}]
  end