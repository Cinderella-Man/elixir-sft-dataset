  @spec edit_distance(String.t(), String.t()) :: non_neg_integer()
  defp edit_distance(a, b) do
    ca = String.to_charlist(a)
    cb = String.to_charlist(b)
    initial = Enum.to_list(0..length(cb))

    ca
    |> Enum.with_index(1)
    |> Enum.reduce(initial, fn {char_a, i}, prev_row ->
      compute_row(char_a, cb, prev_row, i)
    end)
    |> List.last()
  end