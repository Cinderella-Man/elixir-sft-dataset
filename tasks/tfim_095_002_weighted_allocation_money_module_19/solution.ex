  test "split/2 by 1 returns the whole amount" do
    assert Enum.map(Money.split(Money.new(1234, :USD), 1), & &1.amount) == [1234]
  end