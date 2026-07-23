# One bug. Find it. Fix it.

The module below implements the task that follows, except for a single
behavior bug. The bottom of this prompt shows the real failure report from
its (hidden) test suite. Deliver the full corrected module: smallest
possible change, no restructuring, nothing else touched.

## Target behavior

Build me a self-contained Elixir in-memory context module for a `Document` resource with **trash-and-purge soft delete** governed by a retention window. This is a pure Elixir/OTP task — no Phoenix, no Ecto, no database. State lives in a `GenServer` and time is injectable so retention can be tested deterministically.

## Overview

Unlike a plain `deleted_at` flag, a soft-deleted ("trashed") document has a *bounded* second life: it can be restored only while it is inside its retention window. Once `retention_ms` has elapsed since it was trashed, the document becomes **expired** — no longer restorable — and is eligible to be permanently **purged**. This gives three derived states from a single `deleted_at` field plus the clock:

- `:active`  — `deleted_at == nil`
- `:trashed` — `deleted_at` set and `now - deleted_at < retention_ms`
- `:expired` — `deleted_at` set and `now - deleted_at >= retention_ms`

## Module: `SoftCrud.Documents`

A `GenServer`. `start_link(opts)` accepts:

- `:clock` — a zero-arity function returning the current time in integer milliseconds (default `fn -> System.system_time(:millisecond) end`).
- `:retention_ms` — how long a trashed document stays restorable (default 30 days).

A document is a map: `%{id, title, content, deleted_at, inserted_at, updated_at}` where timestamps come from the injected clock.

Functions (all take the server pid/ref first):

- `create_document(server, attrs)` — validates `title` (non-empty string) and `content` (non-empty string). Returns `{:ok, document}` or `{:error, errors}` where `errors` is a map like `%{title: ["can't be blank"]}`. `attrs` may use atom or string keys.
- `list_documents(server, opts \\ [])` — returns documents sorted by id. By default only `:active`. With `include_deleted: true`, returns active, trashed, and expired (anything still stored).
- `get_document(server, id, opts \\ [])` — `{:ok, document}` or `{:error, :not_found}`. By default a trashed or expired document returns `{:error, :not_found}`; with `include_deleted: true` it is returned.
- `update_document(server, id, attrs)` — updates `title` and/or `content` (partial updates allowed) of an `:active` document. Returns `{:ok, document}`, `{:error, errors}`, or `{:error, :not_found}` if the document is missing, trashed, or expired. `deleted_at` can never be set through this function.
- `soft_delete_document(server, id)` — sets `deleted_at` to `clock.()` for an active document → `{:ok, document}`. If already trashed/expired, no-op returning `{:ok, document}`. `{:error, :not_found}` if missing.
- `restore_document(server, id)` — clears `deleted_at` of a `:trashed` document → `{:ok, document}`. No-op `{:ok, document}` for an already-active document. Returns `{:error, :expired}` for an expired document (retention lapsed). `{:error, :not_found}` if missing.
- `purge_document(server, id)` — hard-deletes a trashed or expired document, returning `{:ok, document}`. Returns `{:error, :not_deleted}` for an active document and `{:error, :not_found}` if missing.
- `purge_expired(server)` — permanently removes every currently `:expired` document. Returns `{:ok, purged_count}`.

## Project structure

Use module prefix `SoftCrud`. Put everything in `lib/soft_crud/documents.ex`. Use only the standard library and OTP.

## The buggy module

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

  defp status(%{deleted_at: nil}, _now, _retention), do: :active

  defp status(%{deleted_at: da}, now, retention) do
    if now - da > retention, do: :expired, else: :trashed
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

## Failing test report

```
3 of 26 test(s) failed:

  * test restore_document/2 and retention expired document cannot be restored
      
      
      match (=) failed
      code:  assert {:error, :expired} = Documents.restore_document(srv, doc.id)
      left:  {:error, :expired}
      right: {:ok, %{id: 1, title: "T", content: "C", deleted_at: nil, inserted_at: 0, updated_at: 1000}}
      

  * test purge purge_expired removes only expired documents
      
      
      match (=) failed
      code:  assert {:ok, 1} = Documents.purge_expired(srv)
      left:  {:ok, 1}
      right: {:ok, 0}
      

  * test full lifecycle create -> trash -> expire -> purge
      
      
      match (=) failed
      code:  assert {:error, :expired} = Documents.restore_document(srv, doc.id)
      left:  {:error, :expired}
      right: {:ok, %{id: 1, title: "Life", content: "v2", deleted_at: nil, inserted_at: 0, updated_at: 1000}}
```
