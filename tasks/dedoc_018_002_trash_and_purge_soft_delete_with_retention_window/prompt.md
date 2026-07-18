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
defmodule SoftCrud.Documents do
  use GenServer

  @default_retention_ms 30 * 24 * 60 * 60 * 1000

  # ---- Client API ----

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts)

  def create_document(server, attrs), do: GenServer.call(server, {:create, attrs})

  def list_documents(server, opts \\ []), do: GenServer.call(server, {:list, opts})

  def get_document(server, id, opts \\ []), do: GenServer.call(server, {:get, id, opts})

  def update_document(server, id, attrs), do: GenServer.call(server, {:update, id, attrs})

  def soft_delete_document(server, id), do: GenServer.call(server, {:soft_delete, id})

  def restore_document(server, id), do: GenServer.call(server, {:restore, id})

  def purge_document(server, id), do: GenServer.call(server, {:purge, id})

  def purge_expired(server), do: GenServer.call(server, :purge_expired)

  # ---- Server ----

  @impl true
  def init(opts) do
    clock = Keyword.get(opts, :clock, fn -> System.system_time(:millisecond) end)
    retention = Keyword.get(opts, :retention_ms, @default_retention_ms)
    {:ok, %{docs: %{}, next_id: 1, clock: clock, retention: retention}}
  end

  @impl true
  def handle_call({:create, attrs}, _from, state) do
    case validate_fields(attrs, [:title, :content]) do
      {:ok, f} ->
        now = state.clock.()
        id = state.next_id

        doc = %{
          id: id,
          title: f.title,
          content: f.content,
          deleted_at: nil,
          inserted_at: now,
          updated_at: now
        }

        {:reply, {:ok, doc}, %{state | docs: Map.put(state.docs, id, doc), next_id: id + 1}}

      {:error, errors} ->
        {:reply, {:error, errors}, state}
    end
  end

  def handle_call({:list, opts}, _from, state) do
    now = state.clock.()
    include_deleted = Keyword.get(opts, :include_deleted, false)

    docs =
      state.docs
      |> Map.values()
      |> Enum.sort_by(& &1.id)
      |> Enum.filter(fn doc ->
        include_deleted or status(doc, now, state.retention) == :active
      end)

    {:reply, docs, state}
  end

  def handle_call({:get, id, opts}, _from, state) do
    now = state.clock.()
    include_deleted = Keyword.get(opts, :include_deleted, false)

    reply =
      case Map.get(state.docs, id) do
        nil ->
          {:error, :not_found}

        doc ->
          if status(doc, now, state.retention) == :active or include_deleted do
            {:ok, doc}
          else
            {:error, :not_found}
          end
      end

    {:reply, reply, state}
  end

  def handle_call({:update, id, attrs}, _from, state) do
    now = state.clock.()

    case active_doc(state, id, now) do
      nil ->
        {:reply, {:error, :not_found}, state}

      doc ->
        case validate_update(attrs, doc) do
          {:ok, ch} ->
            updated = %{doc | title: ch.title, content: ch.content, updated_at: now}
            {:reply, {:ok, updated}, %{state | docs: Map.put(state.docs, id, updated)}}

          {:error, errors} ->
            {:reply, {:error, errors}, state}
        end
    end
  end

  def handle_call({:soft_delete, id}, _from, state) do
    now = state.clock.()

    case Map.get(state.docs, id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      doc ->
        case status(doc, now, state.retention) do
          :active ->
            updated = %{doc | deleted_at: now, updated_at: now}
            {:reply, {:ok, updated}, %{state | docs: Map.put(state.docs, id, updated)}}

          _ ->
            {:reply, {:ok, doc}, state}
        end
    end
  end

  def handle_call({:restore, id}, _from, state) do
    now = state.clock.()

    case Map.get(state.docs, id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      doc ->
        case status(doc, now, state.retention) do
          :active ->
            {:reply, {:ok, doc}, state}

          :trashed ->
            updated = %{doc | deleted_at: nil, updated_at: now}
            {:reply, {:ok, updated}, %{state | docs: Map.put(state.docs, id, updated)}}

          :expired ->
            {:reply, {:error, :expired}, state}
        end
    end
  end

  def handle_call({:purge, id}, _from, state) do
    now = state.clock.()

    case Map.get(state.docs, id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      doc ->
        case status(doc, now, state.retention) do
          :active -> {:reply, {:error, :not_deleted}, state}
          _ -> {:reply, {:ok, doc}, %{state | docs: Map.delete(state.docs, id)}}
        end
    end
  end

  def handle_call(:purge_expired, _from, state) do
    now = state.clock.()

    {expired, kept} =
      Enum.split_with(state.docs, fn {_id, doc} ->
        status(doc, now, state.retention) == :expired
      end)

    {:reply, {:ok, length(expired)}, %{state | docs: Map.new(kept)}}
  end

  # ---- Helpers ----

  defp status(%{deleted_at: nil}, _now, _retention), do: :active

  defp status(%{deleted_at: da}, now, retention) do
    if now - da >= retention, do: :expired, else: :trashed
  end

  defp active_doc(state, id, now) do
    case Map.get(state.docs, id) do
      nil -> nil
      doc -> if status(doc, now, state.retention) == :active, do: doc, else: nil
    end
  end

  defp validate_fields(attrs, fields) do
    {values, errors} =
      Enum.reduce(fields, {%{}, %{}}, fn field, {vals, errs} ->
        val = get_field(attrs, field)

        if present?(val) do
          {Map.put(vals, field, val), errs}
        else
          {vals, Map.put(errs, field, ["can't be blank"])}
        end
      end)

    if errors == %{}, do: {:ok, values}, else: {:error, errors}
  end

  defp validate_update(attrs, doc) do
    title = get_field(attrs, :title) || doc.title
    content = get_field(attrs, :content) || doc.content

    errors =
      %{}
      |> check(:title, title)
      |> check(:content, content)

    if errors == %{}, do: {:ok, %{title: title, content: content}}, else: {:error, errors}
  end

  defp check(errors, field, value) do
    if present?(value), do: errors, else: Map.put(errors, field, ["can't be blank"])
  end

  defp present?(value), do: is_binary(value) and String.trim(value) != ""

  defp get_field(attrs, key) do
    cond do
      Map.has_key?(attrs, key) -> Map.get(attrs, key)
      Map.has_key?(attrs, Atom.to_string(key)) -> Map.get(attrs, Atom.to_string(key))
      true -> nil
    end
  end
end
```
