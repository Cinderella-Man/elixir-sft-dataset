  test "to_string/1 formats 3-decimal currencies" do
    assert Money.to_string(Money.new(1_234_567, :BHD)) == "1234.567 BHD"
    assert Money.to_string(Money.new(7, :KWD)) == "0.007 KWD"
  end