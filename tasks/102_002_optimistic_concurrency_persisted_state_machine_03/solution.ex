  @spec load_latest(module(), String.t()) :: {state_name(), non_neg_integer()}
  defp load_latest(repo, entity_id) do
    query =
      from(t in EntityTransition,
        where: t.entity_id == ^entity_id,
        order_by: [desc: t.version, desc: t.id],
        limit: 1
      )

    case repo.one(query) do
      nil ->
        {@initial_state, 0}

      %EntityTransition{to_state: to_state, version: version} ->
        {String.to_existing_atom(to_state), version}
    end
  end