  test "push is rejected with {:error, :full} at capacity" do
    {:ok, buf} = RejectingRingBuffer.new(2) |> RejectingRingBuffer.push(1)
    {:ok, buf} = RejectingRingBuffer.push(buf, 2)
    assert RejectingRingBuffer.full?(buf)
    assert {:error, :full} = RejectingRingBuffer.push(buf, 3)
  end