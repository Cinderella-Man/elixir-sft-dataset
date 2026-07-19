# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `init` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Build me a self-contained Elixir in-memory context module for a `Document` resource with soft delete guarded by **optimistic concurrency** (version-checked writes). This is a pure Elixir/OTP task — no Phoenix, no Ecto, no database. State lives in a `GenServer`, which serializes writes so lost updates are provably impossible.

## Overview

Every document carries a monotonically increasing `lock_version` (starting at `0`). Each mutating operation — update, soft delete, restore — must be given the `expected_version` the caller last observed. If it does not match the document's current `lock_version`, the write is rejected with `{:error, :stale_version, current_version}` and no state changes. A successful mutation bumps `lock_version` by one. This lets many concurrent writers race safely: exactly one wins, the rest are told they hold a stale view.

## Module: `SoftCrud.Documents`

A `GenServer`. `start_link(opts \\ [])` takes no required options. `attrs` may use atom or string keys.

A document is a map: `%{id, title, content, deleted_at, lock_version, inserted_at, updated_at}` (`deleted_at` is `nil` when active, a stamp when soft-deleted).

Validation errors are returned as `{:error, errors}`, where `errors` is a map keyed by the offending field name (`:title` and/or `:content`) with a non-empty value (e.g. a list of messages); an absent field means it passed. A `title` or `content` is blank when it is not a binary or trims to `""`.

Functions (server pid/ref first):

- `create_document(server, attrs)` — validates non-empty `title` and `content`. Returns `{:ok, document}` (with `lock_version: 0`) or `{:error, errors}`. On error nothing is stored.
- `list_documents(server, opts \\ [])` — active only by default; `include_deleted: true` for all. Sorted by id ascending.
- `get_document(server, id, opts \\ [])` — `{:ok, document}` or `{:error, :not_found}`; soft-deleted hidden unless `include_deleted: true`.
- `update_document(server, id, attrs, expected_version)` — updates `title`/`content` (partial allowed) of an active document; unrecognized keys (e.g. `deleted_at`) are ignored. Precedence: `{:error, :not_found}` if missing **or** soft-deleted; then `{:error, :stale_version, current}` on version mismatch; then `{:error, errors}` on invalid attrs; else `{:ok, document}` with `lock_version + 1`. Never sets `deleted_at`.
- `soft_delete_document(server, id, expected_version)` — precedence: `{:error, :not_found}` if missing; then `{:error, :stale_version, current}` on mismatch; then `{:error, :already_deleted}` if already soft-deleted; else soft-deletes → `{:ok, document}` with `lock_version + 1` and a non-nil `deleted_at`.
- `restore_document(server, id, expected_version)` — precedence: `{:error, :not_found}` if missing; then `{:error, :stale_version, current}` on mismatch; then `{:error, :not_deleted}` if already active; else restores → `{:ok, document}` with `lock_version + 1` and `deleted_at` back to `nil`.

Because the GenServer processes calls one at a time, a burst of concurrent `soft_delete_document(id, 0)` requests must yield exactly one `{:ok, _}` and the rest `{:error, :stale_version, 1}`.

## Project structure

Use module prefix `SoftCrud`. Put everything in `lib/soft_crud/documents.ex`. Use only the standard library and OTP.

## The module with `init` missing

```elixir
defmodule SoftCrud.Documents do
  @moduledoc """
  In-memory document store with soft delete guarded by optimistic concurrency.

  Each document carries a `lock_version` (starting at 0). Every mutation must be
  given the `expected_version`; a mismatch yields `{:error, :stale_version,
  current}` with no state change. A successful mutation bumps `lock_version`.
  The GenServer serializes writes, so concurrent racers cannot lose updates.
  """

  use GenServer

  @typedoc "A running server: a pid, a registered name, or a `{:via, _, _}` ref."
  @type server :: GenServer.server()

  @typedoc "Attributes for create/update; keys may be atoms or strings."
  @type attrs :: map()

  @typedoc "Validation errors keyed by field name."
  @type errors :: %{optional(atom()) => [String.t()]}

  @typedoc "A stored document record."
  @type document :: %{
          id: pos_integer(),
          title: String.t(),
          content: String.t(),
          deleted_at: integer() | nil,
          lock_version: non_neg_integer(),
          inserted_at: integer(),
          updated_at: integer()
        }

  # ---- Client API ----

  @doc """
  Starts the document store `GenServer`. Takes no required options.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts)

  @doc """
  Creates a document with a non-empty `title` and `content`.

  Returns `{:ok, document}` with `lock_version: 0`, or `{:error, errors}`.
  """
  @spec create_document(server(), attrs()) :: {:ok, document()} | {:error, errors()}
  def create_document(s, attrs), do: GenServer.call(s, {:create, attrs})

  @doc """
  Lists documents sorted by id.

  Active documents only by default; pass `include_deleted: true` for all.
  """
  @spec list_documents(server(), keyword()) :: [document()]
  def list_documents(s, opts \\ []), do: GenServer.call(s, {:list, opts})

  @doc """
  Fetches a document by `id`.

  Returns `{:ok, document}` or `{:error, :not_found}`; soft-deleted documents
  are hidden unless `include_deleted: true` is given.
  """
  @spec get_document(server(), pos_integer(), keyword()) ::
          {:ok, document()} | {:error, :not_found}
  def get_document(s, id, opts \\ []), do: GenServer.call(s, {:get, id, opts})

  @doc """
  Updates `title`/`content` (partial allowed) of an active document.

  Precedence: `{:error, :not_found}` if missing or soft-deleted, then
  `{:error, :stale_version, current}` on mismatch, then `{:error, errors}` on
  invalid attrs, else `{:ok, document}` with `lock_version + 1`.
  """
  @spec update_document(server(), pos_integer(), attrs(), non_neg_integer()) ::
          {:ok, document()}
          | {:error, :not_found}
          | {:error, :stale_version, non_neg_integer()}
          | {:error, errors()}
  def update_document(s, id, attrs, expected_version),
    do: GenServer.call(s, {:update, id, attrs, expected_version})

  @doc """
  Soft-deletes an active document.

  Precedence: `{:error, :not_found}` if missing, then
  `{:error, :stale_version, current}` on mismatch, then `{:error,
  :already_deleted}` if already deleted, else `{:ok, document}`.
  """
  @spec soft_delete_document(server(), pos_integer(), non_neg_integer()) ::
          {:ok, document()}
          | {:error, :not_found | :already_deleted}
          | {:error, :stale_version, non_neg_integer()}
  def soft_delete_document(s, id, expected_version),
    do: GenServer.call(s, {:soft_delete, id, expected_version})

  @doc """
  Restores a soft-deleted document.

  Precedence: `{:error, :not_found}` if missing, then
  `{:error, :stale_version, current}` on mismatch, then `{:error,
  :not_deleted}` if already active, else `{:ok, document}`.
  """
  @spec restore_document(server(), pos_integer(), non_neg_integer()) ::
          {:ok, document()}
          | {:error, :not_found | :not_deleted}
          | {:error, :stale_version, non_neg_integer()}
  def restore_document(s, id, expected_version),
    do: GenServer.call(s, {:restore, id, expected_version})

  # ---- Server ----

  def init(_opts) do
    # TODO
  end

  @doc false
  @impl true
  @spec handle_call(term(), GenServer.from(), map()) :: {:reply, term(), map()}
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

Give me only the complete implementation of `init` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
