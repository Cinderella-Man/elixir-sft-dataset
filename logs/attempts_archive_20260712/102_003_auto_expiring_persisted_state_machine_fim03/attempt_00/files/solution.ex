  @spec load_state(module(), String.t()) :: state()
  defp load_state(repo, entity_id) do
    query =
      from(t in EntityTransition,
        where: t.entity_id == ^entity_id,
        order_by: [desc: t.id],
        limit: 1,
        select: t.to_state
      )

    case repo.one(query) do
      nil -> :pending
      to_state -> String.to_existing_atom(to_state)
    end
  end