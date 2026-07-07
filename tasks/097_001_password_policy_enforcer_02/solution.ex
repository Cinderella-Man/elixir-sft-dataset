  defp do_levenshtein(a_graphs, b_graphs, _m, n) do
    # `prev` holds the distances for the previous row (i-1).
    # Initialise for i = 0: distance from "" to b[0..j] = j.
    prev = Enum.to_list(0..n) |> List.to_tuple()

    a_graphs
    |> Enum.with_index(1)
    |> Enum.reduce(prev, fn {a_char, i}, prev_row ->
      # curr[0] = i  (distance from a[0..i] to "")
      curr_row =
        b_graphs
        |> Enum.with_index(1)
        |> Enum.reduce({[i], i}, fn {b_char, j}, {acc, left} ->
          diag = elem(prev_row, j - 1)   # prev[j-1]
          up   = elem(prev_row, j)        # prev[j]

          cost = if a_char == b_char, do: 0, else: 1

          val = Enum.min([
            left + 1,        # deletion
            up   + 1,        # insertion
            diag + cost      # substitution (or match)
          ])

          {[val | acc], val}
        end)
        |> elem(0)
        |> Enum.reverse()
        |> List.to_tuple()

      curr_row
    end)
    |> elem(n)   # bottom-right cell = final distance
  end