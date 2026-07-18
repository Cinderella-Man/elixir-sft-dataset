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
defmodule ConditionalObjectStorage do
  use GenServer

  @name_regex ~r/\A[a-z0-9.-]+\z/

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  def start_link(opts \\ []) do
    {name, rest} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, rest, server_opts)
  end

  def create_bucket(server, name) do
    GenServer.call(server, {:create_bucket, name})
  end

  def list_buckets(server) do
    GenServer.call(server, :list_buckets)
  end

  def put_object(server, bucket, key, data, opts \\ []) when is_binary(data) do
    GenServer.call(server, {:put_object, bucket, key, data, opts})
  end

  def get_object(server, bucket, key, opts \\ []) do
    GenServer.call(server, {:get_object, bucket, key, opts})
  end

  def delete_object(server, bucket, key, opts \\ []) do
    GenServer.call(server, {:delete_object, bucket, key, opts})
  end

  def list_objects(server, bucket) do
    GenServer.call(server, {:list_objects, bucket})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(_opts) do
    {:ok, %{buckets: %{}}}
  end

  @impl true
  def handle_call({:create_bucket, name}, _from, state) do
    cond do
      not valid_bucket_name?(name) ->
        {:reply, {:error, :invalid_name}, state}

      Map.has_key?(state.buckets, name) ->
        {:reply, {:error, :already_exists}, state}

      true ->
        new_state = put_in(state.buckets[name], %{})
        {:reply, :ok, new_state}
    end
  end

  def handle_call(:list_buckets, _from, state) do
    names = state.buckets |> Map.keys() |> Enum.sort()
    {:reply, {:ok, names}, state}
  end

  def handle_call({:put_object, bucket, key, data, opts}, _from, state) do
    case Map.fetch(state.buckets, bucket) do
      :error ->
        {:reply, {:error, :bucket_not_found}, state}

      {:ok, objects} ->
        do_put_object(state, bucket, objects, key, data, opts)
    end
  end

  def handle_call({:get_object, bucket, key, opts}, _from, state) do
    with {:ok, objects} <- fetch_bucket(state, bucket),
         {:ok, object} <- fetch_object(objects, key) do
      if Keyword.get(opts, :if_none_match) == object.etag do
        {:reply, {:error, :not_modified}, state}
      else
        view = Map.take(object, [:data, :etag, :size, :last_modified])
        {:reply, {:ok, view}, state}
      end
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:delete_object, bucket, key, opts}, _from, state) do
    case Map.fetch(state.buckets, bucket) do
      :error ->
        {:reply, {:error, :bucket_not_found}, state}

      {:ok, objects} ->
        do_delete_object(state, bucket, objects, key, opts)
    end
  end

  def handle_call({:list_objects, bucket}, _from, state) do
    case Map.fetch(state.buckets, bucket) do
      :error ->
        {:reply, {:error, :bucket_not_found}, state}

      {:ok, objects} ->
        entries =
          objects
          |> Enum.map(fn {key, object} ->
            object
            |> Map.take([:etag, :size, :last_modified])
            |> Map.put(:key, key)
          end)
          |> Enum.sort_by(& &1.key)

        {:reply, {:ok, entries}, state}
    end
  end

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  defp do_put_object(state, bucket, objects, key, data, opts) do
    if put_precondition_met?(objects, key, opts) do
      object = build_object(data)
      new_objects = Map.put(objects, key, object)
      new_state = put_in(state.buckets[bucket], new_objects)
      {:reply, {:ok, object.etag}, new_state}
    else
      {:reply, {:error, :precondition_failed}, state}
    end
  end

  defp do_delete_object(state, bucket, objects, key, opts) do
    case Keyword.fetch(opts, :if_match) do
      :error ->
        new_objects = Map.delete(objects, key)
        new_state = put_in(state.buckets[bucket], new_objects)
        {:reply, :ok, new_state}

      {:ok, expected} ->
        case Map.fetch(objects, key) do
          {:ok, %{etag: ^expected}} ->
            new_objects = Map.delete(objects, key)
            new_state = put_in(state.buckets[bucket], new_objects)
            {:reply, :ok, new_state}

          _other ->
            {:reply, {:error, :precondition_failed}, state}
        end
    end
  end

  defp put_precondition_met?(objects, key, opts) do
    cond do
      Keyword.get(opts, :if_none_match) == "*" ->
        not Map.has_key?(objects, key)

      Keyword.has_key?(opts, :if_match) ->
        expected = Keyword.get(opts, :if_match)

        case Map.fetch(objects, key) do
          {:ok, %{etag: ^expected}} -> true
          _other -> false
        end

      true ->
        true
    end
  end

  defp build_object(data) do
    %{
      data: data,
      etag: etag(data),
      size: byte_size(data),
      last_modified: DateTime.utc_now()
    }
  end

  defp etag(data) do
    :sha256
    |> :crypto.hash(data)
    |> Base.encode16(case: :lower)
  end

  defp fetch_bucket(state, bucket) do
    case Map.fetch(state.buckets, bucket) do
      {:ok, objects} -> {:ok, objects}
      :error -> {:error, :bucket_not_found}
    end
  end

  defp fetch_object(objects, key) do
    case Map.fetch(objects, key) do
      {:ok, object} -> {:ok, object}
      :error -> {:error, :not_found}
    end
  end

  defp valid_bucket_name?(name) when is_binary(name) and name != "" do
    Regex.match?(@name_regex, name)
  end

  defp valid_bucket_name?(_name), do: false
end
```
