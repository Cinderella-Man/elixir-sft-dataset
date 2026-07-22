  @spec load_latest(module(), String.t()) :: {state_name(), non_neg_integer()}
  defp load_latest(repo, entity_id) do
    query =
      from(t in EntityTransition,
        where: t.entity_id == ^entity_id,
        order_by: [desc: t.id],
        limit: 1
      )

    case repo.one(query) do
      nil -> {:draft, 0}
      row -> {String.to_atom(row.to_state), row.approvals}
    end
  end