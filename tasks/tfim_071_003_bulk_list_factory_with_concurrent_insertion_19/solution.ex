  test "sequence/2 counters are independent per name" do
    assert Factory.sequence(:audit_indep_a, fn n -> n end) == 1
    assert Factory.sequence(:audit_indep_a, fn n -> n end) == 2
    assert Factory.sequence(:audit_indep_b, fn n -> n end) == 1
    assert Factory.sequence(:audit_indep_a, fn n -> n end) == 3
    assert Factory.sequence(:audit_indep_b, fn n -> n end) == 2
  end