  test "add/2 raises on currency mismatch" do
    assert_raise ArgumentError, fn ->
      Money.add(Money.new(100, :USD), Money.new(100, :EUR))
    end
  end