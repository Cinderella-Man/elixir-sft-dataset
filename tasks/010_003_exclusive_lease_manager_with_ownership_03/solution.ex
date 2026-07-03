  @impl GenServer
  def handle_call({:acquire, resource, owner}, _from, state) do
    now = state.clock.()

    case fetch_live_lease(state.leases, resource, now) do
      {:ok, lease} ->
        {:reply, {:error, :already_held, lease.owner}, state}

      :expired ->
        lease_id = generate_lease_id()
        new_lease = %{lease_id: lease_id, owner: owner, expires_at: now + state.lease_duration_ms}
        new_leases = Map.put(state.leases, resource, new_lease)
        {:reply, {:ok, lease_id}, %{state | leases: new_leases}}

      :missing ->
        lease_id = generate_lease_id()
        new_lease = %{lease_id: lease_id, owner: owner, expires_at: now + state.lease_duration_ms}
        new_leases = Map.put(state.leases, resource, new_lease)
        {:reply, {:ok, lease_id}, %{state | leases: new_leases}}
    end
  end

  def handle_call({:release, resource, owner}, _from, state) do
    now = state.clock.()

    case fetch_live_lease(state.leases, resource, now) do
      {:ok, lease} when lease.owner == owner ->
        new_leases = Map.delete(state.leases, resource)
        {:reply, :ok, %{state | leases: new_leases}}

      {:ok, _lease} ->
        {:reply, {:error, :not_held}, state}

      :expired ->
        new_leases = Map.delete(state.leases, resource)
        {:reply, {:error, :not_held}, %{state | leases: new_leases}}

      :missing ->
        {:reply, {:error, :not_held}, state}
    end
  end

  def handle_call({:renew, resource, owner}, _from, state) do
    now = state.clock.()

    case fetch_live_lease(state.leases, resource, now) do
      {:ok, lease} when lease.owner == owner ->
        new_expires_at = now + state.lease_duration_ms
        updated_lease = %{lease | expires_at: new_expires_at}
        new_leases = Map.put(state.leases, resource, updated_lease)
        {:reply, {:ok, new_expires_at}, %{state | leases: new_leases}}

      {:ok, _lease} ->
        {:reply, {:error, :not_held}, state}

      :expired ->
        new_leases = Map.delete(state.leases, resource)
        {:reply, {:error, :not_held}, %{state | leases: new_leases}}

      :missing ->
        {:reply, {:error, :not_held}, state}
    end
  end

  def handle_call({:holder, resource}, _from, state) do
    now = state.clock.()

    case fetch_live_lease(state.leases, resource, now) do
      {:ok, lease} ->
        {:reply, {:ok, lease.owner, lease.expires_at}, state}

      :expired ->
        new_leases = Map.delete(state.leases, resource)
        {:reply, {:error, :available}, %{state | leases: new_leases}}

      :missing ->
        {:reply, {:error, :available}, state}
    end
  end

  def handle_call({:force_release, resource}, _from, state) do
    new_leases = Map.delete(state.leases, resource)
    {:reply, :ok, %{state | leases: new_leases}}
  end