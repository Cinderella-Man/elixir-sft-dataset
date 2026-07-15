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
            # Match pattern: bind key and score as variables. Embedding the raw
            # player_id in the head would let match-spec-significant atoms
            # (:_, :"$1", …) match as wildcards instead of as themselves — and
            # the contract allows ANY term as a player id.
            {:"$1", :"$2"},
            # Guard: exactly this key (as a literal term) AND a higher score.
            [{:andalso, {:"=:=", :"$1", {:const, player_id}}, {:>, score, :"$2"}}],
            # Action: rebuild the record around the BOUND key variable —
            # select_replace statically requires the key position to be
            # provably unchanged, so :"$1" (not a literal copy) must stay.
            [{{:"$1", {:const, score}}}]
          }
        ]

        :ets.select_replace(board, match_spec)
        :ok
    end
  end