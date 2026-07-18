  @doc """
  Returns `{:ok, active_score}` for a player at `now`, or `{:error, :not_found}`
  when the player has no active (unexpired) events.
  """
  @spec score(board(), player_id(), integer()) :: {:ok, number()} | {:error, :not_found}
  def score(board, player_id, now) do
    case Enum.find(active_scores(board, now), fn {p, _s} -> p == player_id end) do
      nil -> {:error, :not_found}
      {_p, s} -> {:ok, s}
    end
  end