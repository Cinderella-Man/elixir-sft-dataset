# Document this module

Below is a complete, working, tested Elixir module. Its behavior is correct
and must not change — but every piece of documentation has been stripped.

Add the missing documentation and typespecs:

- a `@moduledoc` that explains what the module does and how it is used,
- a `@doc` for every public function,
- a `@spec` for every public function (add `@type`s where they make the
  specs clearer).

Do not change any behavior: every function clause, guard, and expression
must keep working exactly as it does now. Do not rename anything, do not
"improve" the code, and do not add or remove functions. Give me the
complete documented module in a single file.

## The module

```elixir
defmodule VersionedObjectStorage do
  use GenServer

  @default_root "./versioned_object_storage_data"
  @bucket_suffix ".bin"
  @name_regex ~r/^[a-z0-9.\-]+$/

  # ── Public API ──────────────────────────────────────────────────────────

  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  def create_bucket(server, name) do
    GenServer.call(server, {:create_bucket, name})
  end

  def list_buckets(server) do
    GenServer.call(server, :list_buckets)
  end

  def put_object(server, bucket, key, data, metadata \\ %{}) do
    GenServer.call(server, {:put_object, bucket, key, data, metadata})
  end

  def get_object(server, bucket, key) do
    GenServer.call(server, {:get_object, bucket, key})
  end

  def get_object_version(server, bucket, key, version_id) do
    GenServer.call(server, {:get_object_version, bucket, key, version_id})
  end

  def delete_object(server, bucket, key) do
    GenServer.call(server, {:delete_object, bucket, key})
  end

  def list_versions(server, bucket, key) do
    GenServer.call(server, {:list_versions, bucket, key})
  end

  def delete_version(server, bucket, key, version_id) do
    GenServer.call(server, {:delete_version, bucket, key, version_id})
  end

  def list_objects(server, bucket) do
    GenServer.call(server, {:list_objects, bucket})
  end

  # ── GenServer callbacks ─────────────────────────────────────────────────

  @impl true
  def init(opts) do
    root = Keyword.get(opts, :root_dir, @default_root)
    File.mkdir_p!(root)
    {:ok, %{root_dir: root, buckets: load_buckets(root)}}
  end

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

  # ── Internal helpers ────────────────────────────────────────────────────

  defp valid_name?(name) when is_binary(name) and name != "" do
    Regex.match?(@name_regex, name)
  end

  defp valid_name?(_name), do: false

  defp fetch_bucket(state, bucket) do
    case Map.fetch(state.buckets, bucket) do
      {:ok, keys} -> {:ok, keys}
      :error -> {:error, :bucket_not_found}
    end
  end

  # Runs `fun` on the bucket's key map when it exists, persists the resulting
  # key map, and updates state. `fun` returns `{reply, new_keys}`.
  defp with_bucket(state, bucket, fun) do
    case fetch_bucket(state, bucket) do
      {:ok, keys} ->
        {reply, new_keys} = fun.(keys)
        persist_bucket(state.root_dir, bucket, new_keys)
        {:reply, reply, put_in(state.buckets[bucket], new_keys)}

      error ->
        {:reply, error, state}
    end
  end

  defp prepend_version(keys, key, version) do
    Map.update(keys, key, [version], &[version | &1])
  end

  defp update_key(keys, key, []), do: Map.delete(keys, key)
  defp update_key(keys, key, versions), do: Map.put(keys, key, versions)

  defp build_version(data, metadata, is_delete_marker) do
    %{
      version_id: generate_version_id(),
      is_delete_marker: is_delete_marker,
      data: data,
      metadata: metadata,
      size: byte_size(data),
      last_modified: DateTime.utc_now()
    }
  end

  defp generate_version_id do
    Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
  end

  defp latest_object(keys, key) do
    case Map.get(keys, key, []) do
      [%{is_delete_marker: false} = version | _rest] ->
        {:ok,
         %{
           data: version.data,
           metadata: version.metadata,
           size: version.size,
           version_id: version.version_id,
           last_modified: version.last_modified
         }}

      _other ->
        {:error, :not_found}
    end
  end

  defp fetch_version(keys, key, version_id) do
    versions = Map.get(keys, key, [])

    case Enum.find(versions, &(&1.version_id == version_id)) do
      nil ->
        {:error, :not_found}

      version ->
        {:ok,
         %{
           data: version.data,
           metadata: version.metadata,
           size: version.size,
           version_id: version.version_id,
           is_delete_marker: version.is_delete_marker,
           last_modified: version.last_modified
         }}
    end
  end

  defp summarize(version) do
    %{
      version_id: version.version_id,
      is_delete_marker: version.is_delete_marker,
      size: version.size,
      last_modified: version.last_modified
    }
  end

  defp current_objects(keys) do
    keys
    |> Enum.reduce([], fn {key, versions}, acc ->
      case versions do
        [%{is_delete_marker: false} = version | _rest] ->
          entry = %{
            key: key,
            size: version.size,
            version_id: version.version_id,
            last_modified: version.last_modified
          }

          [entry | acc]

        _other ->
          acc
      end
    end)
    |> Enum.sort_by(& &1.key)
  end

  # ── Persistence ─────────────────────────────────────────────────────────

  defp load_buckets(root) do
    case File.ls(root) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, @bucket_suffix))
        |> Enum.reduce(%{}, fn file, acc -> load_bucket_file(root, file, acc) end)

      _error ->
        %{}
    end
  end

  defp load_bucket_file(root, file, acc) do
    name = String.replace_suffix(file, @bucket_suffix, "")

    case File.read(Path.join(root, file)) do
      {:ok, binary} -> Map.put(acc, name, :erlang.binary_to_term(binary))
      _error -> acc
    end
  end

  defp persist_bucket(root, name, keys) do
    path = Path.join(root, name <> @bucket_suffix)
    File.write!(path, :erlang.term_to_binary(keys))
    :ok
  end
end
```
