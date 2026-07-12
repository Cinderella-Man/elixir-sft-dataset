  @spec load_latest_state(module(), String.t()) :: atom()
  defp load_latest_state(repo, entity_id) do
    query =
      from(t in EntityTransition,
        where: t.entity_id == ^entity_id,
        order_by: [desc: t.inserted_at],
        limit: 1
      )

    case repo.one(query) do
      nil -> @initial_state
      record -> String.to_existing_atom(record.to_state)
    end
  end