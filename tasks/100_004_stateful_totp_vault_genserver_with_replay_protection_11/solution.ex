  @impl true
  def handle_call({:register, account_id}, _from, state) do
    case Map.fetch(state, account_id) do
      {:ok, _account} ->
        {:reply, {:error, :already_registered}, state}

      :error ->
        secret = generate_secret()
        account = %{secret: secret, last: nil}
        {:reply, {:ok, secret}, Map.put(state, account_id, account)}
    end
  end

  def handle_call({:secret, account_id}, _from, state) do
    case Map.fetch(state, account_id) do
      {:ok, %{secret: secret}} -> {:reply, {:ok, secret}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:current_code, account_id, time}, _from, state) do
    case Map.fetch(state, account_id) do
      {:ok, %{secret: secret}} ->
        code = hotp(secret, div(time, @step_seconds))
        {:reply, {:ok, code}, state}

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:consume, account_id, code, time, window}, _from, state) do
    case Map.fetch(state, account_id) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, %{secret: secret, last: last} = account} ->
        base = div(time, @step_seconds)

        case match_step(secret, code, base, window) do
          nil ->
            {:reply, {:error, :invalid}, state}

          matched when is_integer(last) and matched <= last ->
            {:reply, {:error, :replayed}, state}

          matched ->
            updated = Map.put(state, account_id, %{account | last: matched})
            {:reply, :ok, updated}
        end
    end
  end