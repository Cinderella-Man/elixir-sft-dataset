  test "allocate/2 respects weight proportions with a remainder" do
    # 100 by [1,2]: shares 33 and 66 (sum 99), remainder 1 -> first party
    parts = Money.allocate(Money.new(100, :USD), [1, 2])
    assert Enum.map(parts, & &1.amount) == [34, 66]
    assert Enum.sum(Enum.map(parts, & &1.amount)) == 100
  end