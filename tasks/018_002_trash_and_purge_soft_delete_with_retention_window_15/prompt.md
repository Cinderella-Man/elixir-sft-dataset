# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `handle_call` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

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

## The module with `handle_call` missing

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

  def handle_call({:create, attrs}, _from, state) do
    # TODO
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

Give me only the complete implementation of `handle_call` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
