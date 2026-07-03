Implement the private `status/3` helper. It classifies a stored document into
one of three derived states given the current time and the retention window.

`status(doc, now, retention)` receives a document map, `now` (the current time in
integer milliseconds, as returned by the injected clock), and `retention` (the
retention window in milliseconds). It must return:

- `:active` when the document's `deleted_at` is `nil`;
- `:expired` when `deleted_at` is set and at least `retention` milliseconds have
  elapsed since it was trashed (i.e. `now - deleted_at >= retention`);
- `:trashed` when `deleted_at` is set but the retention window has not yet lapsed
  (i.e. `now - deleted_at < retention`).

This helper is the single source of truth every server callback consults to decide
whether a document is listable, restorable, or purgeable, so it must depend only on
`deleted_at`, `now`, and `retention` — never on wall-clock time directly.

```elixir
defmodule SoftCrud.Documents do
  @moduledoc """
  In-memory document store with trash-and-purge soft delete governed by a
  retention window. Backed by a GenServer with an injectable clock.

  Derived states from `deleted_at` + clock:

    * `:active`  — deleted_at == nil
    * `:trashed` — deleted_at set, now - deleted_at < retention_ms
    * `:expired` — deleted_at set, now - deleted_at >= retention_ms
  """

  use GenServer

  @default_retention_ms 30 * 24 * 60 * 60 * 1000

  @typedoc "A stored document."
  @type t :: %{
          id: pos_integer(),
          title: String.t(),
          content: String.t(),
          deleted_at: integer() | nil,
          inserted_at: integer(),
          updated_at: integer()
        }

  @typedoc "Validation errors keyed by field."
  @type errors :: %{optional(atom()) => [String.t()]}

  # ---- Client API ----

  @doc """
  Starts the document store.

  Options: `:clock` (zero-arity fn returning integer milliseconds) and
  `:retention_ms` (how long a trashed document stays restorable).
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts)

  @doc """
  Creates a document from `attrs` (atom or string keys).

  Returns `{:ok, document}` or `{:error, errors}` when `title`/`content`
  are missing or blank.
  """
  @spec create_document(GenServer.server(), map()) :: {:ok, t()} | {:error, errors()}
  def create_document(server, attrs), do: GenServer.call(server, {:create, attrs})

  @doc """
  Lists documents sorted by id.

  By default only `:active` documents; pass `include_deleted: true` to
  include trashed and expired documents as well.
  """
  @spec list_documents(GenServer.server(), keyword()) :: [t()]
  def list_documents(server, opts \\ []), do: GenServer.call(server, {:list, opts})

  @doc """
  Fetches a document by `id`.

  Trashed/expired documents return `{:error, :not_found}` unless
  `include_deleted: true` is given.
  """
  @spec get_document(GenServer.server(), pos_integer(), keyword()) ::
          {:ok, t()} | {:error, :not_found}
  def get_document(server, id, opts \\ []), do: GenServer.call(server, {:get, id, opts})

  @doc """
  Updates `title` and/or `content` of an `:active` document.

  Returns `{:ok, document}`, `{:error, errors}`, or `{:error, :not_found}`
  when missing, trashed, or expired. `deleted_at` cannot be set here.
  """
  @spec update_document(GenServer.server(), pos_integer(), map()) ::
          {:ok, t()} | {:error, errors() | :not_found}
  def update_document(server, id, attrs), do: GenServer.call(server, {:update, id, attrs})

  @doc """
  Trashes an active document by setting `deleted_at`.

  A no-op returning `{:ok, document}` for an already trashed/expired
  document; `{:error, :not_found}` if missing.
  """
  @spec soft_delete_document(GenServer.server(), pos_integer()) ::
          {:ok, t()} | {:error, :not_found}
  def soft_delete_document(server, id), do: GenServer.call(server, {:soft_delete, id})

  @doc """
  Restores a `:trashed` document by clearing `deleted_at`.

  A no-op `{:ok, document}` for an active document, `{:error, :expired}`
  for an expired one, and `{:error, :not_found}` if missing.
  """
  @spec restore_document(GenServer.server(), pos_integer()) ::
          {:ok, t()} | {:error, :expired | :not_found}
  def restore_document(server, id), do: GenServer.call(server, {:restore, id})

  @doc """
  Hard-deletes a trashed or expired document.

  Returns `{:error, :not_deleted}` for an active document and
  `{:error, :not_found}` if missing.
  """
  @spec purge_document(GenServer.server(), pos_integer()) ::
          {:ok, t()} | {:error, :not_deleted | :not_found}
  def purge_document(server, id), do: GenServer.call(server, {:purge, id})

  @doc """
  Permanently removes every currently `:expired` document.

  Returns `{:ok, purged_count}`.
  """
  @spec purge_expired(GenServer.server()) :: {:ok, non_neg_integer()}
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

  defp status(doc, now, retention) do
    # TODO
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