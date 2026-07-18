  test "split/2 divides evenly and distributes remainder" do
    assert Enum.map(Money.split(Money.new(900, :USD), 3), & &1.amount) == [300, 300, 300]
    assert Enum.map(Money.split(Money.new(1000, :USD), 3), & &1.amount) == [334, 333, 333]
  end