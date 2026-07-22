  def rank(board, player_id) do
    case :ets.lookup(board.index, player_id) do
      [] ->
        {:error, :not_found}

      [{^player_id, {neg_score, _seq, _pid} = key}] ->
        match_spec = [{{:"$1", :_, :_}, [{:<, :"$1", {:const, key}}], [true]}]
        before = :ets.select_count(board.entries, match_spec)
        {:ok, before + 1, -neg_score}
    end
  end