  test "named process registration works" do
    {:ok, _pid} = ORSet.start_link(name: :my_or_set)
    ORSet.add(:my_or_set, :x, :n1)
    assert ORSet.member?(:my_or_set, :x) == true
  end