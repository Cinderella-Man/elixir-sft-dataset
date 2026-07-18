  @impl true
  def handle_call({:create_bucket, name}, _from, state) do
    cond do
      not valid_name?(name) ->
        {:reply, {:error, :invalid_name}, state}

      Map.has_key?(state.buckets, name) ->
        {:reply, {:error, :already_exists}, state}

      true ->
        persist_bucket(state.root_dir, name, %{})
        {:reply, :ok, put_in(state.buckets[name], %{})}
    end
  end

  def handle_call(:list_buckets, _from, state) do
    {:reply, {:ok, state.buckets |> Map.keys() |> Enum.sort()}, state}
  end

  def handle_call({:put_object, bucket, key, data, metadata}, _from, state) do
    with_bucket(state, bucket, fn keys ->
      version = build_version(data, metadata, false)
      new_keys = prepend_version(keys, key, version)
      {{:ok, version.version_id}, new_keys}
    end)
  end

  def handle_call({:get_object, bucket, key}, _from, state) do
    reply =
      case fetch_bucket(state, bucket) do
        {:ok, keys} -> latest_object(keys, key)
        error -> error
      end

    {:reply, reply, state}
  end

  def handle_call({:get_object_version, bucket, key, version_id}, _from, state) do
    reply =
      case fetch_bucket(state, bucket) do
        {:ok, keys} -> fetch_version(keys, key, version_id)
        error -> error
      end

    {:reply, reply, state}
  end

  def handle_call({:delete_object, bucket, key}, _from, state) do
    with_bucket(state, bucket, fn keys ->
      version = build_version("", %{}, true)
      new_keys = prepend_version(keys, key, version)
      {{:ok, version.version_id}, new_keys}
    end)
  end

  def handle_call({:list_versions, bucket, key}, _from, state) do
    reply =
      case fetch_bucket(state, bucket) do
        {:ok, keys} -> {:ok, Enum.map(Map.get(keys, key, []), &summarize/1)}
        error -> error
      end

    {:reply, reply, state}
  end

  def handle_call({:delete_version, bucket, key, version_id}, _from, state) do
    with_bucket(state, bucket, fn keys ->
      versions = Map.get(keys, key, [])
      kept = Enum.reject(versions, &(&1.version_id == version_id))
      new_keys = update_key(keys, key, kept)
      {:ok, new_keys}
    end)
  end

  def handle_call({:list_objects, bucket}, _from, state) do
    reply =
      case fetch_bucket(state, bucket) do
        {:ok, keys} -> {:ok, current_objects(keys)}
        error -> error
      end

    {:reply, reply, state}
  end