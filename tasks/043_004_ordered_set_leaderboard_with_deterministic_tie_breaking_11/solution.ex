  @doc """
  Submits `score` for `player_id`, keeping only the all-time high.  Serialized
  through the owning GenServer.  Always returns `:ok`.
  """
  @spec submit_score(board(), player_id(), number()) :: :ok
  def submit_score(board, player_id, score) when is_number(score) do
    GenServer.call(board.server, {:submit, player_id, score})
  end