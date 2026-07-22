  defp mask_cc_match(match) do
    chars = String.graphemes(match)
    digit_count = Enum.count(chars, &digit?/1)
    keep_threshold = digit_count - 4

    {reversed, _seen} =
      Enum.reduce(chars, {[], 0}, fn ch, {acc, seen} ->
        if digit?(ch) do
          seen = seen + 1
          replacement = if seen > keep_threshold, do: ch, else: "*"
          {[replacement | acc], seen}
        else
          {[ch | acc], seen}
        end
      end)

    reversed |> Enum.reverse() |> Enum.join()
  end