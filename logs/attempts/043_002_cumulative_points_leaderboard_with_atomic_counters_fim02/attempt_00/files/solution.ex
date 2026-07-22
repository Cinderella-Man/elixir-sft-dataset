  def add_points(board, player_id, points) when is_integer(points) do
    new_total = :ets.update_counter(board, player_id, points, {player_id, 0})
    {:ok, new_total}
  end