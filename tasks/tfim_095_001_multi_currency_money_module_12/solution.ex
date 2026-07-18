  test "subtract/2 raises on currency mismatch" do
    assert_raise ArgumentError, fn ->
      Money.subtract(Money.new(500, :USD), Money.new(100, :GBP))
    end
  end