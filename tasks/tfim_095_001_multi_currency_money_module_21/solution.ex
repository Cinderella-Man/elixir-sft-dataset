  test "split/2 returns exactly n parts" do
    assert length(Money.split(Money.new(1000, :USD), 7)) == 7
  end