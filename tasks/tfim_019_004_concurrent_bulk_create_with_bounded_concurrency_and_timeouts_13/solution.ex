  test "the concurrency bound holds even when tasks are killed by timeout" do
    # A killed task never runs its own cleanup — the tracker must not leak its
    # slot upward. One slow item times out (killed), then fast items follow;
    # a leaked slot would let the high-water mark read max_concurrency + 1.
    items = [
      %{"name" => "slow", "price" => 1, "delay" => 400}
      | for(k <- 2..5, do: %{"name" => "n#{k}", "price" => k, "delay" => 30})
    ]

    results = ConcurrentCatalog.bulk_create(items, max_concurrency: 2, timeout_ms: 120)

    assert {0, :error, :timeout} = Enum.at(results, 0)
    assert Enum.all?(Enum.drop(results, 1), fn {_i, tag, _} -> tag == :ok end)
    assert ConcurrentCatalog.peak() <= 2
  end