  test "split/2 by 1 returns the original amount in a single-element list" do
    parts = Money.split(Money.new(1234, :USD), 1)
    assert Enum.map(parts, & &1.amount) == [1234]
  end