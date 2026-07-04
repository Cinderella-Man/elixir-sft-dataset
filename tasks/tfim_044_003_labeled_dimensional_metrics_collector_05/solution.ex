  test "increment supports name+amount without labels" do
    Metrics.increment(:bytes, 500)
    Metrics.increment(:bytes, 250)
    assert Metrics.get(:bytes, %{}) == 750
  end