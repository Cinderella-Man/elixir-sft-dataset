# Add moduledoc, docs, and specs

Below: a correct, tested, undocumented module. Deliver the same module
fully documented — a `@moduledoc`, a per-public-function `@doc` and
`@spec`, and supporting `@type`s where useful. Behavior, names, structure:
unchanged. One file.

## The module

```elixir
defmodule TtlObjectStorage do
  use GenServer

  # `\A`/`\z` (not `^`/`$`) so that a trailing newline cannot sneak past the anchors.
  @name_regex ~r/\A[a-z0-9.-]+\z/

  ## Public API

  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    default_ttl = Keyword.get(opts, :default_ttl_ms, :infinity)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, %{default_ttl_ms: default_ttl}, gen_opts)
  end

  def create_bucket(server, name) do
    GenServer.call(server, {:create_bucket, name})
  end

  def list_buckets(server) do
    GenServer.call(server, :list_buckets)
  end

  def delete_bucket(server, name) do
    GenServer.call(server, {:delete_bucket, name})
  end

  def put_object(server, bucket, key, data, opts \\ []) when is_binary(data) do
    GenServer.call(server, {:put_object, bucket, key, data, opts})
  end

  def get_object(server, bucket, key) do
    GenServer.call(server, {:get_object, bucket, key})
  end

  def delete_object(server, bucket, key) do
    GenServer.call(server, {:delete_object, bucket, key})
  end

  def list_objects(server, bucket) do
    GenServer.call(server, {:list_objects, bucket})
  end

  def set_ttl(server, bucket, key, ttl_ms) do
    GenServer.call(server, {:set_ttl, bucket, key, ttl_ms})
  end

  def purge_expired(server) do
    GenServer.call(server, :purge_expired)
  end

  ## GenServer callbacks

  @impl true
  def init(%{default_ttl_ms: default_ttl}) do
    {:ok, %{default_ttl_ms: default_ttl, buckets: %{}}}
  end

  @impl true
  def handle_call({:create_bucket, name}, _from, state) do
    cond do
      not valid_name?(name) ->
        {:reply, {:error, :invalid_name}, state}

      Map.has_key?(state.buckets, name) ->
        {:reply, {:error, :already_exists}, state}

      true ->
        buckets = Map.put(state.buckets, name, %{})
        {:reply, :ok, %{state | buckets: buckets}}
    end
  end

  def handle_call(:list_buckets, _from, state) do
    {:reply, {:ok, Enum.sort(Map.keys(state.buckets))}, state}
  end

  def handle_call({:delete_bucket, name}, _from, state) do
    case Map.fetch(state.buckets, name) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, objects} ->
        now = now_ms()

        if Enum.any?(objects, fn {_key, obj} -> not expired?(obj, now) end) do
          {:reply, {:error, :not_empty}, state}
        else
          {:reply, :ok, %{state | buckets: Map.delete(state.buckets, name)}}
        end
    end
  end

  def handle_call({:put_object, bucket, key, data, opts}, _from, state) do
    case Map.fetch(state.buckets, bucket) do
      :error ->
        {:reply, {:error, :bucket_not_found}, state}

      {:ok, objects} ->
        ttl = Keyword.get(opts, :ttl_ms, state.default_ttl_ms)
        now = now_ms()

        object = %{
          data: data,
          size: byte_size(data),
          last_modified: DateTime.utc_now(),
          expires_at: compute_expires_at(ttl, now)
        }

        objects = Map.put(objects, key, object)
        {:reply, :ok, put_bucket(state, bucket, objects)}
    end
  end

  def handle_call({:get_object, bucket, key}, _from, state) do
    case Map.fetch(state.buckets, bucket) do
      :error ->
        {:reply, {:error, :bucket_not_found}, state}

      {:ok, objects} ->
        now = now_ms()

        case Map.fetch(objects, key) do
          {:ok, obj} ->
            if expired?(obj, now) do
              objects = Map.delete(objects, key)
              {:reply, {:error, :not_found}, put_bucket(state, bucket, objects)}
            else
              reply = {:ok, Map.take(obj, [:data, :size, :last_modified])}
              {:reply, reply, state}
            end

          :error ->
            {:reply, {:error, :not_found}, state}
        end
    end
  end

  def handle_call({:delete_object, bucket, key}, _from, state) do
    case Map.fetch(state.buckets, bucket) do
      :error ->
        {:reply, {:error, :bucket_not_found}, state}

      {:ok, objects} ->
        objects = Map.delete(objects, key)
        {:reply, :ok, put_bucket(state, bucket, objects)}
    end
  end

  def handle_call({:list_objects, bucket}, _from, state) do
    case Map.fetch(state.buckets, bucket) do
      :error ->
        {:reply, {:error, :bucket_not_found}, state}

      {:ok, objects} ->
        now = now_ms()

        listing =
          objects
          |> Enum.reject(fn {_key, obj} -> expired?(obj, now) end)
          |> Enum.map(fn {key, obj} ->
            %{key: key, size: obj.size, last_modified: obj.last_modified}
          end)
          |> Enum.sort_by(& &1.key)

        {:reply, {:ok, listing}, state}
    end
  end

  def handle_call({:set_ttl, bucket, key, ttl_ms}, _from, state) do
    case Map.fetch(state.buckets, bucket) do
      :error ->
        {:reply, {:error, :bucket_not_found}, state}

      {:ok, objects} ->
        now = now_ms()

        case Map.fetch(objects, key) do
          {:ok, obj} ->
            if expired?(obj, now) do
              objects = Map.delete(objects, key)
              {:reply, {:error, :not_found}, put_bucket(state, bucket, objects)}
            else
              obj = %{obj | expires_at: compute_expires_at(ttl_ms, now)}
              objects = Map.put(objects, key, obj)
              {:reply, :ok, put_bucket(state, bucket, objects)}
            end

          :error ->
            {:reply, {:error, :not_found}, state}
        end
    end
  end

  def handle_call(:purge_expired, _from, state) do
    now = now_ms()

    {buckets, removed} =
      Enum.reduce(state.buckets, {%{}, 0}, fn {name, objects}, {acc, count} ->
        live = Enum.reject(objects, fn {_key, obj} -> expired?(obj, now) end)
        removed = map_size(objects) - length(live)
        {Map.put(acc, name, Map.new(live)), count + removed}
      end)

    {:reply, {:ok, removed}, %{state | buckets: buckets}}
  end

  ## Internal helpers

  defp put_bucket(state, bucket, objects) do
    %{state | buckets: Map.put(state.buckets, bucket, objects)}
  end

  defp valid_name?(name) when is_binary(name) and name != "" do
    Regex.match?(@name_regex, name)
  end

  defp valid_name?(_name), do: false

  defp now_ms, do: System.monotonic_time(:millisecond)

  defp compute_expires_at(:infinity, _now), do: :infinity
  defp compute_expires_at(ttl_ms, now), do: now + ttl_ms

  defp expired?(%{expires_at: :infinity}, _now), do: false
  defp expired?(%{expires_at: expires_at}, now), do: now >= expires_at
end
```
