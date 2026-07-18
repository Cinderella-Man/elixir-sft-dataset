  test "increment accepts zero at the non-negative boundary and leaves the value alone" do
    Metrics.increment(:bytes, %{route: "/z"}, 0)
    assert Metrics.get(:bytes, %{route: "/z"}) == 0

    Metrics.increment(:bytes, %{route: "/z"}, 4)
    Metrics.increment(:bytes, %{route: "/z"}, 0)
    assert Metrics.get(:bytes, %{route: "/z"}) == 4

    Metrics.increment(:bytes, 0)
    assert Metrics.get(:bytes, %{}) == 0
  end