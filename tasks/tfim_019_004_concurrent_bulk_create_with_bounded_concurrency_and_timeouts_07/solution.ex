  test "items exceeding the timeout are reported as :timeout and not inserted" do
    items = [
      %{"name" => "fast", "price" => 1},
      %{"name" => "slow", "price" => 2, "delay" => 200},
      %{"name" => "fast2", "price" => 3}
    ]

    results = ConcurrentCatalog.bulk_create(items, max_concurrency: 3, timeout_ms: 60)

    assert {0, :ok, _} = Enum.at(results, 0)
    assert {1, :error, :timeout} = Enum.at(results, 1)
    assert {2, :ok, _} = Enum.at(results, 2)

    assert ConcurrentCatalog.count() == 2
    refute Enum.any?(ConcurrentCatalog.all(), fn item -> item.name == "slow" end)
  end