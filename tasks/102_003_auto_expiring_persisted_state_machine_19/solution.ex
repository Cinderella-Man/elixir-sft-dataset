  @doc """
  Attempts to transition `entity_id` via `event`.

  Returns `{:ok, new_state}` on a valid transition (persisting first),
  `{:error, :invalid_transition}` for an invalid `(state, event)` pair,
  `{:error, :not_found}` if the entity has not been started, or
  `{:error, {:db_error, reason}}` if persistence fails (in which case the
  in-memory state is left unchanged).
  """
  @spec transition(GenServer.server(), String.t(), event()) ::
          {:ok, state()}
          | {:error, :invalid_transition | :not_found | {:db_error, term()}}
  def transition(server, entity_id, event) do
    GenServer.call(server, {:transition, entity_id, event})
  end