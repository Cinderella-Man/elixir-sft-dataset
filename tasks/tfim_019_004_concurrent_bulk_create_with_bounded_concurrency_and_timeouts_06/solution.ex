  test "max_concurrency 1 runs serially" do
    items = for k <- 1..4, do: %{"name" => "n#{k}", "price" => k, "delay" => 10}

    results = ConcurrentCatalog.bulk_create(items, max_concurrency: 1, timeout_ms: 1000)

    assert Enum.all?(results, fn {_i, tag, _} -> tag == :ok end)
    assert ConcurrentCatalog.count() == 4
    assert ConcurrentCatalog.peak() == 1
  end