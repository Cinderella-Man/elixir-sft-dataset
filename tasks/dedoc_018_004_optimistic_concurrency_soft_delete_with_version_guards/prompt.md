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

  # ---- Client API ----

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts)

  def create_document(s, attrs), do: GenServer.call(s, {:create, attrs})

  def list_documents(s, opts \\ []), do: GenServer.call(s, {:list, opts})

  def get_document(s, id, opts \\ []), do: GenServer.call(s, {:get, id, opts})

  def update_document(s, id, attrs, expected_version),
    do: GenServer.call(s, {:update, id, attrs, expected_version})

  def soft_delete_document(s, id, expected_version),
    do: GenServer.call(s, {:soft_delete, id, expected_version})

  def restore_document(s, id, expected_version),
    do: GenServer.call(s, {:restore, id, expected_version})

  # ---- Server ----

  @impl true
  def init(_opts), do: {:ok, %{docs: %{}, next_id: 1, tick: 1}}

  @impl true
  def handle_call({:create, attrs}, _from, state) do
    case validate_fields(attrs, [:title, :content]) do
      {:ok, f} ->
        id = state.next_id
        t = state.tick

        doc = %{
          id: id,
          title: f.title,
          content: f.content,
          deleted_at: nil,
          lock_version: 0,
          inserted_at: t,
          updated_at: t
        }

        {:reply, {:ok, doc},
         %{state | docs: Map.put(state.docs, id, doc), next_id: id + 1, tick: t + 1}}

      {:error, errors} ->
        {:reply, {:error, errors}, state}
    end
  end

  def handle_call({:list, opts}, _from, state) do
    include_deleted = Keyword.get(opts, :include_deleted, false)

    res =
      state.docs
      |> Map.values()
      |> Enum.sort_by(& &1.id)
      |> Enum.filter(fn d -> include_deleted or d.deleted_at == nil end)

    {:reply, res, state}
  end

  def handle_call({:get, id, opts}, _from, state) do
    include_deleted = Keyword.get(opts, :include_deleted, false)

    reply =
      case Map.get(state.docs, id) do
        nil -> {:error, :not_found}
        d -> if d.deleted_at == nil or include_deleted, do: {:ok, d}, else: {:error, :not_found}
      end

    {:reply, reply, state}
  end

  def handle_call({:update, id, attrs, expected}, _from, state) do
    case Map.get(state.docs, id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %{deleted_at: da} when da != nil ->
        {:reply, {:error, :not_found}, state}

      %{lock_version: v} when v != expected ->
        {:reply, {:error, :stale_version, v}, state}

      doc ->
        case validate_update(attrs, doc) do
          {:ok, ch} ->
            t = state.tick

            updated = %{
              doc
              | title: ch.title,
                content: ch.content,
                lock_version: doc.lock_version + 1,
                updated_at: t
            }

            docs = Map.put(state.docs, id, updated)
            {:reply, {:ok, updated}, %{state | docs: docs, tick: t + 1}}

          {:error, errors} ->
            {:reply, {:error, errors}, state}
        end
    end
  end

  def handle_call({:soft_delete, id, expected}, _from, state) do
    case Map.get(state.docs, id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %{lock_version: v} when v != expected ->
        {:reply, {:error, :stale_version, v}, state}

      %{deleted_at: da} when da != nil ->
        {:reply, {:error, :already_deleted}, state}

      doc ->
        t = state.tick
        updated = %{doc | deleted_at: t, lock_version: doc.lock_version + 1, updated_at: t}
        {:reply, {:ok, updated}, %{state | docs: Map.put(state.docs, id, updated), tick: t + 1}}
    end
  end

  def handle_call({:restore, id, expected}, _from, state) do
    case Map.get(state.docs, id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %{lock_version: v} when v != expected ->
        {:reply, {:error, :stale_version, v}, state}

      %{deleted_at: nil} ->
        {:reply, {:error, :not_deleted}, state}

      doc ->
        t = state.tick
        updated = %{doc | deleted_at: nil, lock_version: doc.lock_version + 1, updated_at: t}
        {:reply, {:ok, updated}, %{state | docs: Map.put(state.docs, id, updated), tick: t + 1}}
    end
  end

  # ---- Helpers ----

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
