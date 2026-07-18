  test "split/2 handles more parties than cents" do
    # 2 cents among 3 -> [1, 1, 0]
    parts = Money.split(Money.new(2, :USD), 3)
    assert Enum.map(parts, & &1.amount) == [1, 1, 0]
    assert Enum.sum(Enum.map(parts, & &1.amount)) == 2
  end