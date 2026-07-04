  test "label order does not matter — same series" do
    Metrics.increment(:hits, %{a: 1, b: 2})
    Metrics.increment(:hits, %{b: 2, a: 1})
    assert Metrics.get(:hits, %{a: 1, b: 2}) == 2
  end