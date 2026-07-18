  test "repeated rejected pushes never change size or contents" do
    buf = RejectingRingBuffer.new(2)
    {:ok, buf} = RejectingRingBuffer.push(buf, :x)
    {:ok, buf} = RejectingRingBuffer.push(buf, :y)

    Enum.each(1..5, fn i ->
      assert {:error, :full} = RejectingRingBuffer.push(buf, i)
    end)

    assert RejectingRingBuffer.size(buf) == 2
    assert RejectingRingBuffer.to_list(buf) == [:x, :y]
    assert {:ok, :x} = RejectingRingBuffer.peek_oldest(buf)
    assert {:ok, :y} = RejectingRingBuffer.peek_newest(buf)
  end