  test "sequence/2 returns distinct values" do
    a = Factory.sequence(:seq_x, fn n -> "x-#{n}" end)
    b = Factory.sequence(:seq_x, fn n -> "x-#{n}" end)
    assert a == "x-1"
    assert b == "x-2"
  end