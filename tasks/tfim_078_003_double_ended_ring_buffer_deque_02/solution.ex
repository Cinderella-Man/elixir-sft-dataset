  test "new deque is empty" do
    d = RingDeque.new(4)
    assert RingDeque.size(d) == 0
    assert RingDeque.to_list(d) == []
    assert :error = RingDeque.peek_front(d)
    assert :error = RingDeque.peek_back(d)
    assert :empty = RingDeque.pop_front(d)
    assert :empty = RingDeque.pop_back(d)
  end