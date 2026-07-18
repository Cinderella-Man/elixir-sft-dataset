  test "new/2 returns a struct carrying exactly the amount and currency fields" do
    m = Money.new(7, :GBP)
    # Map key iteration order is an implementation detail; compare as a set.
    assert Enum.sort(Map.keys(Map.from_struct(m))) == [:amount, :currency]
    assert m.__struct__ == Money
  end