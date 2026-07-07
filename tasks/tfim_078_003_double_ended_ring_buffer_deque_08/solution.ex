  test "push_front at capacity overwrites the back" do
    d =
      RingDeque.new(3)
      |> RingDeque.push_back(1)
      |> RingDeque.push_back(2)
      |> RingDeque.push_back(3)

    d = RingDeque.push_front(d, 0)
    assert RingDeque.size(d) == 3
    assert RingDeque.to_list(d) == [0, 1, 2]

    d = RingDeque.push_front(d, -1)
    assert RingDeque.to_list(d) == [-1, 0, 1]
    assert {:ok, -1} = RingDeque.peek_front(d)
    assert {:ok, 1} = RingDeque.peek_back(d)
  end