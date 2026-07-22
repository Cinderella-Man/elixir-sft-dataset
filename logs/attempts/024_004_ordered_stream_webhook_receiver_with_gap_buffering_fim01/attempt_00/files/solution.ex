  defp drain(last_seq, buffer, delivered, event) do
    delivered = delivered ++ [event]
    last_seq = last_seq + 1

    case Map.pop(buffer, last_seq + 1) do
      {nil, _buffer} -> {last_seq, buffer, delivered}
      {next, rest} -> drain(last_seq, rest, delivered, %{next | status: :delivered})
    end
  end