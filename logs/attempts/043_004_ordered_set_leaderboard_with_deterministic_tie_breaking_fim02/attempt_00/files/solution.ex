@impl true
def handle_call(:board, _from, state) do
  board = %{server: self(), entries: state.entries, index: state.index}
  {:reply, {:ok, board}, state}
end

@impl true
def handle_call({:submit, player_id, score}, _from, state) do
  seq = state.seq

  case :ets.lookup(state.index, player_id) do
    [] ->
      insert_entry(state, player_id, score, seq)
      {:reply, :ok, %{state | seq: seq + 1}}

    [{^player_id, {old_neg, _old_seq, _old_pid} = old_key}] ->
      old_score = -old_neg

      if score > old_score do
        :ets.delete(state.entries, old_key)
        insert_entry(state, player_id, score, seq)
        {:reply, :ok, %{state | seq: seq + 1}}
      else
        {:reply, :ok, state}
      end
  end
end