  @spec mask_cc(String.t()) :: String.t()
  defp mask_cc(match) do
    graphemes = String.graphemes(match)
    total = Enum.count(graphemes, &digit?/1)

    {chars, _idx} =
      Enum.map_reduce(graphemes, 0, fn ch, idx ->
        if digit?(ch) do
          masked = if idx < total - 4, do: "*", else: ch
          {masked, idx + 1}
        else
          {ch, idx}
        end
      end)

    Enum.join(chars)
  end