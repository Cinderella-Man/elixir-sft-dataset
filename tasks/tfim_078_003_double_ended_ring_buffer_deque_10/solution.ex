  test "capacity-1 deque holds exactly one item from either end" do
    d = RingDeque.new(1)
    d = RingDeque.push_back(d, :a)
    assert RingDeque.to_list(d) == [:a]

    d = RingDeque.push_back(d, :b)
    assert RingDeque.to_list(d) == [:b]

    d = RingDeque.push_front(d, :c)
    assert RingDeque.to_list(d) == [:c]
    assert {:ok, :c} = RingDeque.peek_front(d)
    assert {:ok, :c} = RingDeque.peek_back(d)
  end