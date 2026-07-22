def lookup(pid \\ self()) do
  ensure_registry()

  Agent.get(@registry, fn s ->
    owner = Map.get(s.allow, pid)

    cond do
      Map.has_key?(s.owners, pid) ->
        {:ok, s.owners[pid]}

      owner != nil and Map.has_key?(s.owners, owner) ->
        {:ok, s.owners[owner]}

      s.shared != nil and Map.has_key?(s.owners, s.shared) ->
        {:ok, s.owners[s.shared]}

      true ->
        :error
    end
  end)
end