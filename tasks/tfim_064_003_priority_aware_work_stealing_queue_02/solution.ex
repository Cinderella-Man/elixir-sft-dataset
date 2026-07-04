  test "all payloads are returned exactly once" do
    items = for p <- 1..20, do: {p, p * 100}
    results = WorkStealQueue.run(items, 4, fn payload -> payload + 1 end)

    assert length(results) == 20
    expected_payloads = Enum.map(items, fn {_p, payload} -> payload end)
    assert Enum.sort(payloads(results)) == Enum.sort(expected_payloads)
    assert length(Enum.uniq_by(results, & &1.item)) == 20
  end