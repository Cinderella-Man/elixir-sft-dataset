  test "results carry the correct computed value and priority" do
    items = [{5, 5}, {1, 1}, {3, 3}, {2, 2}, {4, 4}]
    results = WorkStealQueue.run(items, 2, fn payload -> payload * payload end)

    by_payload = Map.new(results, fn r -> {r.item, r} end)

    for {priority, payload} <- items do
      r = by_payload[payload]
      assert r.result == payload * payload
      assert r.priority == priority
    end
  end