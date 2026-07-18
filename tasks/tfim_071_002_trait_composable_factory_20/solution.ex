  test "distinct sequence names keep independent counters" do
    a1 = Factory.sequence(:seq_indep_a, fn n -> n end)
    a2 = Factory.sequence(:seq_indep_a, fn n -> n end)
    b1 = Factory.sequence(:seq_indep_b, fn n -> n end)
    a3 = Factory.sequence(:seq_indep_a, fn n -> n end)
    b2 = Factory.sequence(:seq_indep_b, fn n -> n end)
    assert [a1, a2, a3] == [1, 2, 3]
    assert [b1, b2] == [1, 2]
  end