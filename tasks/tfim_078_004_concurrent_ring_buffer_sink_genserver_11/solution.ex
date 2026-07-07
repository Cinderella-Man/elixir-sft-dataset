  test "concurrent writers never corrupt the buffer" do
    {:ok, pid} = ConcurrentRingBuffer.start_link(capacity: 10)

    1..1000
    |> Task.async_stream(fn i -> ConcurrentRingBuffer.push(pid, i) end,
      max_concurrency: 50,
      ordered: false
    )
    |> Stream.run()

    assert ConcurrentRingBuffer.size(pid) == 10
    list = ConcurrentRingBuffer.to_list(pid)
    assert length(list) == 10
    assert Enum.all?(list, fn x -> is_integer(x) and x in 1..1000 end)
    # No duplicate slots / corruption: all held values are distinct.
    assert length(Enum.uniq(list)) == 10
  end