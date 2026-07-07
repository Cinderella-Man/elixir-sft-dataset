  test "push_back at capacity overwrites the front" do
    d =
      RingDeque.new(3)
      |> RingDeque.push_back(1)
      |> RingDeque.push_back(2)
      |> RingDeque.push_back(3)

    assert RingDeque.to_list(d) == [1, 2, 3]

    d = RingDeque.push_back(d, 4)
    assert RingDeque.size(d) == 3
    assert RingDeque.to_list(d) == [2, 3, 4]

    d = RingDeque.push_back(d, 5)
    assert RingDeque.to_list(d) == [3, 4, 5]
    assert {:ok, 3} = RingDeque.peek_front(d)
    assert {:ok, 5} = RingDeque.peek_back(d)
  end