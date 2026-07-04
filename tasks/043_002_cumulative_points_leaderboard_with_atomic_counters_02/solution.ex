  def rank(board, player_id) do
    case :ets.lookup(board, player_id) do
      [] ->
        {:error, :not_found}

      [{^player_id, score}] ->
        match_spec = [{{:_, :"$1"}, [{:>, :"$1", score}], [true]}]
        above = :ets.select_count(board, match_spec)
        {:ok, above + 1, score}
    end
  end