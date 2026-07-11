  test "invalid half_life raises" do
    assert_raise ArgumentError, fn ->
      DecayPercentile.start_link(name: :bad, clock: &Clock.now/0, half_life_ms: 0)
    end
  end