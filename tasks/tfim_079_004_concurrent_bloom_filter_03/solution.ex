  test "adds are visible across processes sharing the handle" do
    filter = ConcurrentBloomFilter.new(100, 0.01)

    task =
      Task.async(fn ->
        ConcurrentBloomFilter.add(filter, "written-elsewhere")
      end)

    Task.await(task)

    # The mutation happened in another process but is visible here because the
    # backing :atomics array is shared.
    assert ConcurrentBloomFilter.member?(filter, "written-elsewhere")
  end