  test "a timing-out item still yields ordered per-index results while tasks overlap" do
    items = [
      %{"name" => "quick1", "price" => 1, "delay" => 20},
      %{"name" => "stuck", "price" => 2, "delay" => 600},
      %{"name" => "quick2", "price" => 3, "delay" => 20},
      %{"name" => "quick3", "price" => 4, "delay" => 20}
    ]

    results = ConcurrentCatalog.bulk_create(items, max_concurrency: 2, timeout_ms: 150)

    # Exactly one result per input item, in original input order.
    assert length(results) == 4
    assert Enum.map(results, fn {i, _tag, _reason} -> i end) == [0, 1, 2, 3]
    assert {0, :ok, %{name: "quick1"}} = Enum.at(results, 0)
    assert {1, :error, :timeout} = Enum.at(results, 1)
    assert {2, :ok, %{name: "quick2"}} = Enum.at(results, 2)
    assert {3, :ok, %{name: "quick3"}} = Enum.at(results, 3)

    # The killed item is never inserted; the surviving items all are.
    assert ConcurrentCatalog.count() == 3
    refute Enum.any?(ConcurrentCatalog.all(), fn item -> item.name == "stuck" end)

    # Work still parallelizes while the long-running item is in flight.
    assert ConcurrentCatalog.peak() >= 2
  end