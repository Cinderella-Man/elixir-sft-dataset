  @doc """
  Returns the top `n` players as `{player_id, score}` tuples in leaderboard
  order.  Reads the ordered set directly in key order.
  """
  @spec top(board(), non_neg_integer()) :: [{player_id(), number()}]
  def top(_board, 0), do: []

  def top(board, n) when is_integer(n) and n > 0 do
    take_first(board.entries, :ets.first(board.entries), n, [])
  end