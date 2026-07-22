def top(_board, 0), do: []

def top(board, n) when is_integer(n) and n > 0 do
  board
  |> :ets.tab2list()
  |> Enum.sort_by(fn {_player_id, score} -> score end, &>=/2)
  |> Enum.take(n)
end