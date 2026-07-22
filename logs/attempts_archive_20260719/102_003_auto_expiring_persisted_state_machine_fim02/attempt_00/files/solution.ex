  @spec persist(module(), String.t(), event(), state(), state()) ::
          :ok | {:error, term()}
  defp persist(repo, entity_id, event, from_state, to_state) do
    row = %EntityTransition{
      entity_id: entity_id,
      event: Atom.to_string(event),
      from_state: Atom.to_string(from_state),
      to_state: Atom.to_string(to_state),
      inserted_at: DateTime.utc_now()
    }

    case repo.insert(row) do
      {:ok, _record} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end