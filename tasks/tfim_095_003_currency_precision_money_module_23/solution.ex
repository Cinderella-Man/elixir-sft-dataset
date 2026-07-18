  test "round-trip from_major then to_string is stable" do
    m = Money.from_major(19.99, :USD)
    assert m.amount == 1999
    assert Money.to_string(m) == "19.99 USD"
  end