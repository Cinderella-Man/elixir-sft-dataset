  test "concurrent readers and writers stay consistent" do
    {:ok, pid} = ConcurrentRingBuffer.start_link(capacity: 8)

    writers =
      Task.async(fn ->
        Enum.each(1..500, &ConcurrentRingBuffer.push(pid, &1))
      end)

    readers =
      Task.async(fn ->
        Enum.map(1..200, fn _ ->
          list = ConcurrentRingBuffer.to_list(pid)
          # size of any snapshot must never exceed capacity
          assert length(list) <= 8
          length(list)
        end)
      end)

    Task.await(writers)
    Task.await(readers)

    assert ConcurrentRingBuffer.size(pid) == 8
  end