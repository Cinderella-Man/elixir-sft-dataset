  test "different sequence names are independent counters" do
    a1 = Factory.sequence(:seq_a, fn n -> "a-#{n}" end)
    b1 = Factory.sequence(:seq_b, fn n -> "b-#{n}" end)
    a2 = Factory.sequence(:seq_a, fn n -> "a-#{n}" end)
    b2 = Factory.sequence(:seq_b, fn n -> "b-#{n}" end)

    assert a1 == "a-1"
    assert b1 == "b-1"
    assert a2 == "a-2"
    assert b2 == "b-2"
  end