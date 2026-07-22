@spec load_history(module(), String.t()) :: [map()]
defp load_history(repo, entity_id) do
  query =
    from(t in EntityTransition,
      where: t.entity_id == ^entity_id,
      order_by: [asc: t.id]
    )

  query
  |> repo.all()
  |> Enum.map(fn t ->
    %{
      event: String.to_existing_atom(t.event),
      from_state: String.to_existing_atom(t.from_state),
      to_state: String.to_existing_atom(t.to_state),
      version: t.version,
      inserted_at: t.inserted_at
    }
  end)
end