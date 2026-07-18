  @impl true
  def handle_call({:create_bucket, name}, _from, state) do
    with :ok <- validate_bucket_name(name) do
      bucket_path = bucket_dir(state, name)

      if File.dir?(bucket_path) do
        {:reply, {:error, :already_exists}, state}
      else
        File.mkdir_p!(objects_dir(state, name))
        {:reply, :ok, state}
      end
    else
      {:error, _} = err -> {:reply, err, state}
    end
  end

  # ── delete_bucket ──────────────────────────────────────────

  def handle_call({:delete_bucket, name}, _from, state) do
    bucket_path = bucket_dir(state, name)

    cond do
      not File.dir?(bucket_path) ->
        {:reply, {:error, :not_found}, state}

      not bucket_empty?(state, name) ->
        {:reply, {:error, :not_empty}, state}

      true ->
        File.rm_rf!(bucket_path)
        {:reply, :ok, state}
    end
  end

  # ── list_buckets ───────────────────────────────────────────

  def handle_call(:list_buckets, _from, state) do
    buckets =
      state.buckets_dir
      |> File.ls!()
      |> Enum.filter(&File.dir?(Path.join(state.buckets_dir, &1)))
      |> Enum.sort()

    {:reply, {:ok, buckets}, state}
  end

  # ── put_object ─────────────────────────────────────────────

  def handle_call({:put_object, bucket, key, data, content_type, metadata}, _from, state) do
    if not bucket_exists?(state, bucket) do
      {:reply, {:error, :bucket_not_found}, state}
    else
      write_object(state, bucket, key, data, content_type, metadata)
      {:reply, :ok, state}
    end
  end

  # ── get_object ─────────────────────────────────────────────

  def handle_call({:get_object, bucket, key}, _from, state) do
    cond do
      not bucket_exists?(state, bucket) ->
        {:reply, {:error, :bucket_not_found}, state}

      not object_exists?(state, bucket, key) ->
        {:reply, {:error, :not_found}, state}

      true ->
        {:reply, {:ok, read_object(state, bucket, key)}, state}
    end
  end

  # ── delete_object ──────────────────────────────────────────

  def handle_call({:delete_object, bucket, key}, _from, state) do
    if not bucket_exists?(state, bucket) do
      {:reply, {:error, :bucket_not_found}, state}
    else
      data_path = object_data_path(state, bucket, key)
      meta_path = object_meta_path(state, bucket, key)
      File.rm(data_path)
      File.rm(meta_path)
      {:reply, :ok, state}
    end
  end

  # ── list_objects ───────────────────────────────────────────

  def handle_call({:list_objects, bucket, opts}, _from, state) do
    if not bucket_exists?(state, bucket) do
      {:reply, {:error, :bucket_not_found}, state}
    else
      prefix = Keyword.get(opts, :prefix, "")
      max_keys = Keyword.get(opts, :max_keys, 1000)

      objects =
        state
        |> all_object_keys(bucket)
        |> Enum.filter(&String.starts_with?(&1, prefix))
        |> Enum.sort()
        |> Enum.take(max_keys)
        |> Enum.map(&object_summary(state, bucket, &1))

      {:reply, {:ok, objects}, state}
    end
  end

  # ── copy_object ────────────────────────────────────────────

  def handle_call({:copy_object, src_bucket, src_key, dst_bucket, dst_key}, _from, state) do
    cond do
      not bucket_exists?(state, src_bucket) ->
        {:reply, {:error, :src_bucket_not_found}, state}

      not bucket_exists?(state, dst_bucket) ->
        {:reply, {:error, :dst_bucket_not_found}, state}

      not object_exists?(state, src_bucket, src_key) ->
        {:reply, {:error, :not_found}, state}

      src_bucket == dst_bucket and src_key == dst_key ->
        {:reply, :ok, state}

      true ->
        obj = read_object(state, src_bucket, src_key)
        write_object(state, dst_bucket, dst_key, obj.data, obj.content_type, obj.metadata)
        {:reply, :ok, state}
    end
  end

  # ── start_multipart ────────────────────────────────────────

  def handle_call({:start_multipart, bucket, key, content_type, metadata}, _from, state) do
    if not bucket_exists?(state, bucket) do
      {:reply, {:error, :bucket_not_found}, state}
    else
      upload_id = generate_upload_id()

      upload = %{
        bucket: bucket,
        key: key,
        content_type: content_type,
        metadata: metadata,
        parts: %{}
      }

      state = put_in(state, [:multipart_uploads, upload_id], upload)
      {:reply, {:ok, upload_id}, state}
    end
  end

  # ── upload_part ────────────────────────────────────────────

  def handle_call({:upload_part, upload_id, part_number, data}, _from, state) do
    case Map.fetch(state.multipart_uploads, upload_id) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, _upload} ->
        state = put_in(state, [:multipart_uploads, upload_id, :parts, part_number], data)
        {:reply, :ok, state}
    end
  end

  # ── complete_multipart ─────────────────────────────────────

  def handle_call({:complete_multipart, upload_id}, _from, state) do
    case Map.fetch(state.multipart_uploads, upload_id) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, %{parts: parts}} when map_size(parts) == 0 ->
        {:reply, {:error, :no_parts}, state}

      {:ok, upload} ->
        assembled =
          upload.parts
          |> Enum.sort_by(fn {part_num, _data} -> part_num end)
          |> Enum.map(fn {_part_num, data} -> data end)
          |> IO.iodata_to_binary()

        write_object(
          state,
          upload.bucket,
          upload.key,
          assembled,
          upload.content_type,
          upload.metadata
        )

        state = %{state | multipart_uploads: Map.delete(state.multipart_uploads, upload_id)}
        {:reply, :ok, state}
    end
  end

  # ── abort_multipart ────────────────────────────────────────

  def handle_call({:abort_multipart, upload_id}, _from, state) do
    if Map.has_key?(state.multipart_uploads, upload_id) do
      state = %{state | multipart_uploads: Map.delete(state.multipart_uploads, upload_id)}
      {:reply, :ok, state}
    else
      {:reply, {:error, :not_found}, state}
    end
  end