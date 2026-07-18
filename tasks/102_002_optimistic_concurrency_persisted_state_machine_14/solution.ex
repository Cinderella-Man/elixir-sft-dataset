  defp persist(repo, entity_id, event, from_state, to_state, version) do
    attrs = %{
      entity_id: entity_id,
      event: Atom.to_string(event),
      from_state: Atom.to_string(from_state),
      to_state: Atom.to_string(to_state),
      version: version,
      inserted_at: DateTime.utc_now()
    }

    %EntityTransition{}
    |> Ecto.Changeset.change(attrs)
    |> repo.insert()
  end