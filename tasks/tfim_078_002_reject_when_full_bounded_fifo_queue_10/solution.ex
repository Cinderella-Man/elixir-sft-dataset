  test "many cycles preserve FIFO correctness" do
    buf = RejectingRingBuffer.new(4)

    final =
      Enum.reduce(1..20, buf, fn i, acc ->
        acc =
          case RejectingRingBuffer.push(acc, i) do
            {:ok, next} -> next
            {:error, :full} -> acc
          end

        # Drain one every other step to force wraparound
        if rem(i, 2) == 0 do
          case RejectingRingBuffer.pop(acc) do
            {:ok, _item, next} -> next
            :empty -> acc
          end
        else
          acc
        end
      end)

    assert RejectingRingBuffer.size(final) <= 4
    assert RejectingRingBuffer.to_list(final) |> Enum.sort() ==
             RejectingRingBuffer.to_list(final)
  end