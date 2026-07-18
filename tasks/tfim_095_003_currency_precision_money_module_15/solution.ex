  test "split/2 works for a 3-decimal currency" do
    parts = Money.split(Money.new(1000, :BHD), 3)
    assert Enum.sum(Enum.map(parts, & &1.amount)) == 1000
  end