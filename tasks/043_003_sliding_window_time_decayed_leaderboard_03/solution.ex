  def rank(board, player_id, now) do
    scores = active_scores(board, now)

    case Enum.find(scores, fn {p, _s} -> p == player_id end) do
      nil ->
        {:error, :not_found}

      {_p, s} ->
        above = Enum.count(scores, fn {_p2, other} -> other > s end)
        {:ok, above + 1, s}
    end
  end