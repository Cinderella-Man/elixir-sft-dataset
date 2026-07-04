  @spec submit_score(board(), player_id(), score()) :: :ok
  def submit_score(board, player_id, score) do
    # :ets.update_counter/4 cannot handle floats, so we use a CAS loop instead.
    # insert_new/2 succeeds only when the key is absent — giving us a fast path
    # for first-time submissions with no race conditions.
    case :ets.insert_new(board, {player_id, score}) do
      true ->
        # Fresh insertion — we're done.
        :ok

      false ->
        # Key already exists; update only when the new score is strictly higher.
        # :ets.select_replace/2 performs the conditional overwrite atomically
        # on the ETS level, so no GenServer is needed.
        match_spec = [
          {
            # Match pattern: {player_id, OldScore}
            {player_id, :"$1"},
            # Guard: new score > existing score
            [{:>, score, :"$1"}],
            # Action: replace the whole object with the new record
            [{:const, {player_id, score}}]
          }
        ]

        :ets.select_replace(board, match_spec)
        :ok
    end
  end