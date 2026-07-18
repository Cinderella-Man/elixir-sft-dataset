  test "each sequence name has an independent counter starting at 1" do
    assert Factory.sequence(:independent_seq_a, fn n -> n end) == 1
    assert Factory.sequence(:independent_seq_b, fn n -> n end) == 1
    assert Factory.sequence(:independent_seq_a, fn n -> n end) == 2
    assert Factory.sequence(:independent_seq_b, fn n -> n end) == 2
  end