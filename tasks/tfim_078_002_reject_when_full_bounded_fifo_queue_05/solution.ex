  test "peek_oldest and peek_newest reflect ends" do
    {:ok, buf} = RejectingRingBuffer.new(4) |> RejectingRingBuffer.push(:first)
    {:ok, buf} = RejectingRingBuffer.push(buf, :second)
    {:ok, buf} = RejectingRingBuffer.push(buf, :third)

    assert {:ok, :first} = RejectingRingBuffer.peek_oldest(buf)
    assert {:ok, :third} = RejectingRingBuffer.peek_newest(buf)
  end