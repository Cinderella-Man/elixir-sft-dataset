  test "sequence/2 counts up from 1 by one on each call" do
    assert Factory.sequence(:counting_seq, fn n -> n end) == 1
    assert Factory.sequence(:counting_seq, fn n -> n end) == 2
    assert Factory.sequence(:counting_seq, fn n -> n end) == 3
  end