  @impl true
  def handle_call({:add_role, role}, _from, state) do
    {:reply, :ok, %{state | roles: MapSet.put(state.roles, role)}}
  end

  def handle_call({:add_inheritance, child, parent}, _from, state) do
    cond do
      not MapSet.member?(state.roles, child) ->
        {:reply, {:error, :unknown_role}, state}

      not MapSet.member?(state.roles, parent) ->
        {:reply, {:error, :unknown_role}, state}

      child == parent ->
        {:reply, {:error, :cycle}, state}

      # If `parent` already reaches `child` via inheritance, then `child` is an
      # ancestor of `parent`; adding child -> parent would close a cycle.
      reachable?(state.inherits, parent, child) ->
        {:reply, {:error, :cycle}, state}

      true ->
        parents = state.inherits |> Map.get(child, MapSet.new()) |> MapSet.put(parent)
        {:reply, :ok, %{state | inherits: Map.put(state.inherits, child, parents)}}
    end
  end

  def handle_call({:grant, role, resource, action}, _from, state) do
    if MapSet.member?(state.roles, role) do
      key = {resource, action}
      set = state.grants |> Map.get(role, MapSet.new()) |> MapSet.put(key)
      {:reply, :ok, %{state | grants: Map.put(state.grants, role, set)}}
    else
      {:reply, {:error, :unknown_role}, state}
    end
  end

  def handle_call({:revoke, role, resource, action}, _from, state) do
    key = {resource, action}
    set = state.grants |> Map.get(role, MapSet.new()) |> MapSet.delete(key)
    {:reply, :ok, %{state | grants: Map.put(state.grants, role, set)}}
  end

  def handle_call({:can?, role, resource, action}, _from, state) do
    result =
      if MapSet.member?(state.roles, role) do
        key = {resource, action}

        state.inherits
        |> closure(role)
        |> Enum.any?(fn r ->
          MapSet.member?(Map.get(state.grants, r, MapSet.new()), key)
        end)
      else
        false
      end

    {:reply, result, state}
  end