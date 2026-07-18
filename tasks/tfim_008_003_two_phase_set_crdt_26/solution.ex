  test "named process registration works" do
    {:ok, _pid} = TwoPhaseSet.start_link(name: :my_2p_set)
    TwoPhaseSet.add(:my_2p_set, :x)
    assert TwoPhaseSet.member?(:my_2p_set, :x) == true
  end