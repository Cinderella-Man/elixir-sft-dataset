  test "sequence/2 formats each counter value through formatter_fn" do
    assert Factory.sequence(:formatted_seq, &"item-#{&1}") == "item-1"
    assert Factory.sequence(:formatted_seq, &"item-#{&1}") == "item-2"
  end