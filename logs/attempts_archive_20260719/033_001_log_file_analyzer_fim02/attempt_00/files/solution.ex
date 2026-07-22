  # Sort descending by count, then ascending alphabetically by message.
  # Take at most 10.
  defp compute_top_errors(error_messages) do
    error_messages
    |> Enum.sort(fn {msg_a, cnt_a}, {msg_b, cnt_b} ->
      cond do
        cnt_a != cnt_b -> cnt_a > cnt_b
        true -> msg_a <= msg_b
      end
    end)
    |> Enum.take(10)
  end