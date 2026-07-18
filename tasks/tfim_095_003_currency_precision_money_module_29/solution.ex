  test "to_string/1 signs negative zero-decimal and 3-decimal amounts" do
    assert Money.to_string(Money.new(-500, :JPY)) == "-500 JPY"
    assert Money.to_string(Money.new(-1_234_567, :BHD)) == "-1234.567 BHD"
    assert Money.to_string(Money.new(-7, :KWD)) == "-0.007 KWD"
  end