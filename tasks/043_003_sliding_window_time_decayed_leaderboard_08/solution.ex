  @doc """
  Returns the top `n` active players at `now`, sorted by active score descending.
  """
  @spec top(board(), non_neg_integer(), integer()) :: [{player_id(), number()}]
  def top(_board, 0, _now), do: []

  def top(board, n, now) when is_integer(n) and n > 0 do
    board
    |> active_scores(now)
    |> Enum.sort_by(fn {_p, s} -> s end, :desc)
    |> Enum.take(n)
  end