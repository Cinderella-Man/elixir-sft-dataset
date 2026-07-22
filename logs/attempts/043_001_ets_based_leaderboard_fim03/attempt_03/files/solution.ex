def top(_board, 0), do: []

def top(board, n) when is_integer(n) and n > 0 do
  board
  |> :ets.tab2list()
  |> Enum.sort(fn {_id_a, score_a}, {_id_b, score_b} -> score_a >= score_b end)
  |> Enum.take(n)
end