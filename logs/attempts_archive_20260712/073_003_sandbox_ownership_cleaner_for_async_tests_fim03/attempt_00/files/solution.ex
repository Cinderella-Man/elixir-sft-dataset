def allow(owner, allowed) when is_pid(owner) and is_pid(allowed) do
  ensure_registry()

  has_owner? = Agent.get(@registry, fn s -> Map.has_key?(s.owners, owner) end)

  if has_owner? do
    Agent.update(@registry, fn s -> put_in(s.allow[allowed], owner) end)
    {:ok, allowed}
  else
    {:error, :no_owner}
  end
end