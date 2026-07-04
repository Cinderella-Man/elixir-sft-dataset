  test "increment supports name+labels+amount" do
    Metrics.increment(:bytes, %{route: "/x"}, 10)
    Metrics.increment(:bytes, %{route: "/x"}, 5)
    assert Metrics.get(:bytes, %{route: "/x"}) == 15
  end