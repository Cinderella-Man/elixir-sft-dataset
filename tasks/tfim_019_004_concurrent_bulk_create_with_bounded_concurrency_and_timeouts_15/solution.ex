  test "max_concurrency defaults to four when the option is omitted" do
    # Eight overlapping items with the default options saturate the default
    # pool: the high-water mark settles on exactly the default bound.
    items = for k <- 1..8, do: %{"name" => "d#{k}", "price" => k, "delay" => 80}

    results = ConcurrentCatalog.bulk_create(items)

    assert Enum.all?(results, fn {_i, tag, _} -> tag == :ok end)
    assert ConcurrentCatalog.count() == 8
    assert ConcurrentCatalog.peak() == 4
  end