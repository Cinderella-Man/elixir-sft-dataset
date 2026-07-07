  test "rejected push leaves buffer contents unchanged" do
    {:ok, buf} = RejectingRingBuffer.new(2) |> RejectingRingBuffer.push(1)
    {:ok, full} = RejectingRingBuffer.push(buf, 2)

    assert {:error, :full} = RejectingRingBuffer.push(full, 99)
    # original 'full' buffer is untouched
    assert RejectingRingBuffer.to_list(full) == [1, 2]
    assert RejectingRingBuffer.size(full) == 2
  end