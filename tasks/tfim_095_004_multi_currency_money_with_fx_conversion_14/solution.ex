  test "convert/3 handles negative amounts" do
    assert Money.convert(Money.new(-100, :EUR), :USD, @rates).amount == -110
  end