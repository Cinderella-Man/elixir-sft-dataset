  @doc """
  Attempt to apply `event` to `entity_id`.

  On a valid transition, persists a transition row (new state + event +
  resulting approval count), updates the in-memory state and returns
  `{:ok, new_state, new_approval_count}`.

  Returns `{:error, :invalid_transition}` (writing nothing) for an invalid
  `(state, event)` pair, `{:error, :not_found}` if the entity has not been
  started, or `{:error, {:db_error, reason}}` if persistence fails (the
  in-memory state is left unchanged in that case).
  """
  @spec transition(server(), String.t(), event()) ::
          {:ok, state_name(), non_neg_integer()}
          | {:error, :invalid_transition | :not_found | {:db_error, term()}}
  def transition(server, entity_id, event) do
    GenServer.call(server, {:transition, entity_id, event})
  end