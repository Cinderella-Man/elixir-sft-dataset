  test "works with mixed value types" do
    buf =
      RingBuffer.new(5)
      |> RingBuffer.push(42)
      |> RingBuffer.push("hello")
      |> RingBuffer.push(:atom)
      |> RingBuffer.push({:tuple, 1})
      |> RingBuffer.push([1, 2, 3])

    assert RingBuffer.to_list(buf) == [42, "hello", :atom, {:tuple, 1}, [1, 2, 3]]
  end