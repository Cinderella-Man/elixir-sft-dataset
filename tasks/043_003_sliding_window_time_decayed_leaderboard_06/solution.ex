  @doc """
  Records a scoring event of `points` for `player_id` at `now`.  Atomic insert.
  """
  @spec record(board(), player_id(), number(), integer()) :: :ok
  def record({tid, _window}, player_id, points, now)
      when is_number(points) and is_integer(now) do
    :ets.insert(tid, {player_id, now, points})
    :ok
  end