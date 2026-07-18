  defp compute_row(char_a, cb, prev_row, i) do
    pairs = Enum.zip([cb, prev_row, tl(prev_row)])

    {reversed, _left} =
      Enum.reduce(pairs, {[i], i}, fn {char_b, diag, above}, {acc, left} ->
        cost = if char_a == char_b, do: 0, else: 1
        value = Enum.min([above + 1, left + 1, diag + cost])
        {[value | acc], value}
      end)

    Enum.reverse(reversed)
  end