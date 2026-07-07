  test "operations wrap around the backing tuple" do
    d = RingDeque.new(3)
    d = RingDeque.push_back(d, :a)
    d = RingDeque.push_back(d, :b)
    d = RingDeque.push_back(d, :c)

    {:ok, :a, d} = RingDeque.pop_front(d)
    {:ok, :b, d} = RingDeque.pop_front(d)
    # head is now deep into the tuple; push_back must wrap
    d = RingDeque.push_back(d, :d)
    d = RingDeque.push_back(d, :e)
    assert RingDeque.to_list(d) == [:c, :d, :e]

    # push_front must also wrap the head backwards
    {:ok, :e, d} = RingDeque.pop_back(d)
    d = RingDeque.push_front(d, :x)
    assert RingDeque.to_list(d) == [:x, :c, :d]
  end