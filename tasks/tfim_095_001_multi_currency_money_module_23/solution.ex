  test "split/2 preserves currency in every part" do
    parts = Money.split(Money.new(1000, :GBP), 3)
    assert Enum.all?(parts, &(&1.currency == :GBP))
  end