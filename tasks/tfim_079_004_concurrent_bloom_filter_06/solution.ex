  test "concurrent adds from many processes lose no items" do
    filter = ConcurrentBloomFilter.new(5_000, 0.01)
    items = for i <- 1..5_000, do: "concurrent-#{i}"

    items
    |> Task.async_stream(
      fn item -> ConcurrentBloomFilter.add(filter, item) end,
      max_concurrency: 16,
      ordered: false
    )
    |> Stream.run()

    for item <- items do
      assert ConcurrentBloomFilter.member?(filter, item),
             "Expected #{inspect(item)} to survive concurrent insertion"
    end
  end