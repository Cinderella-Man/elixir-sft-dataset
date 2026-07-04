  test "never exceeds the configured concurrency bound" do
    items = for k <- 1..6, do: %{"name" => "n#{k}", "price" => k, "delay" => 40}

    results = ConcurrentCatalog.bulk_create(items, max_concurrency: 2, timeout_ms: 1000)

    assert Enum.all?(results, fn {_i, tag, _} -> tag == :ok end)
    assert ConcurrentCatalog.count() == 6
    assert length(ConcurrentCatalog.all()) == 6
    assert ConcurrentCatalog.peak() <= 2
    assert ConcurrentCatalog.peak() == 2
  end