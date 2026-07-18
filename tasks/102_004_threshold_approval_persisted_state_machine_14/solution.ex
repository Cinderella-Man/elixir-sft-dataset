  @spec fetch_history(module(), String.t()) :: [map()]
  defp fetch_history(repo, entity_id) do
    query =
      from(t in EntityTransition,
        where: t.entity_id == ^entity_id,
        order_by: [asc: t.id]
      )

    query
    |> repo.all()
    |> Enum.map(fn row ->
      %{
        event: String.to_atom(row.event),
        from_state: String.to_atom(row.from_state),
        to_state: String.to_atom(row.to_state),
        approvals: row.approvals,
        inserted_at: row.inserted_at
      }
    end)
  end