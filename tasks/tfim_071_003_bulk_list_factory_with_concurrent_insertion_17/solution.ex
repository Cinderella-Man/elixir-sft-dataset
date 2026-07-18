  test "sequence/2 returns distinct consecutive values" do
    a = Factory.sequence(:s2, fn n -> n end)
    b = Factory.sequence(:s2, fn n -> n end)
    assert a != b
  end