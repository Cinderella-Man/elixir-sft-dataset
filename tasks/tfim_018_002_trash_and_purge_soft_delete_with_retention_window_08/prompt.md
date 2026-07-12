# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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

## Test harness — implement the `# TODO` test

```elixir
defmodule SoftCrud.DocumentsTest do
  use ExUnit.Case, async: false

  alias SoftCrud.Documents

  setup do
    {:ok, clock} = Agent.start_link(fn -> 0 end)
    now = fn -> Agent.get(clock, & &1) end
    advance = fn ms -> Agent.update(clock, &(&1 + ms)) end
    {:ok, srv} = Documents.start_link(clock: now, retention_ms: 1000)
    {:ok, srv: srv, advance: advance}
  end

  defp create(srv, attrs \\ %{}) do
    {:ok, doc} = Documents.create_document(srv, Map.merge(%{title: "T", content: "C"}, attrs))
    doc
  end

  describe "create_document/2" do
    test "creates with valid attrs", %{srv: srv} do
      {:ok, doc} = Documents.create_document(srv, %{title: "My Doc", content: "Hello"})
      assert doc.id
      assert doc.title == "My Doc"
      assert doc.content == "Hello"
      assert doc.deleted_at == nil
      assert is_integer(doc.inserted_at)
      assert is_integer(doc.updated_at)
    end

    test "rejects missing title", %{srv: srv} do
      assert {:error, errors} = Documents.create_document(srv, %{content: "Hello"})
      assert errors[:title]
    end

    test "rejects empty title", %{srv: srv} do
      assert {:error, errors} = Documents.create_document(srv, %{title: "", content: "Hello"})
      assert errors[:title]
    end

    test "rejects missing content", %{srv: srv} do
      assert {:error, errors} = Documents.create_document(srv, %{title: "A"})
      assert errors[:content]
    end

    test "accepts string keys", %{srv: srv} do
      assert {:ok, doc} = Documents.create_document(srv, %{"title" => "S", "content" => "K"})
      assert doc.title == "S"
    end
  end

  describe "list_documents/2" do
    test "empty by default", %{srv: srv} do
      assert Documents.list_documents(srv) == []
    end

    test "excludes trashed by default, includes with flag", %{srv: srv} do
      # TODO
    end
  end

  describe "get_document/3" do
    test "returns active document", %{srv: srv} do
      doc = create(srv)
      assert {:ok, got} = Documents.get_document(srv, doc.id)
      assert got.id == doc.id
    end

    test "404 for missing id", %{srv: srv} do
      assert {:error, :not_found} = Documents.get_document(srv, 999)
    end

    test "trashed hidden by default, visible with flag", %{srv: srv} do
      doc = create(srv)
      {:ok, _} = Documents.soft_delete_document(srv, doc.id)
      assert {:error, :not_found} = Documents.get_document(srv, doc.id)
      assert {:ok, got} = Documents.get_document(srv, doc.id, include_deleted: true)
      assert got.deleted_at != nil
    end
  end

  describe "update_document/3" do
    test "updates title and content", %{srv: srv} do
      doc = create(srv, %{title: "Old", content: "Old"})
      {:ok, up} = Documents.update_document(srv, doc.id, %{title: "New", content: "New!"})
      assert up.title == "New"
      assert up.content == "New!"
    end

    test "partial update keeps other field", %{srv: srv} do
      doc = create(srv, %{title: "Old", content: "Keep"})
      {:ok, up} = Documents.update_document(srv, doc.id, %{title: "New"})
      assert up.title == "New"
      assert up.content == "Keep"
    end

    test "rejects empty title", %{srv: srv} do
      doc = create(srv)
      assert {:error, errors} = Documents.update_document(srv, doc.id, %{title: ""})
      assert errors[:title]
    end

    test "404 for missing and for trashed", %{srv: srv} do
      assert {:error, :not_found} = Documents.update_document(srv, 999, %{title: "x"})
      doc = create(srv)
      {:ok, _} = Documents.soft_delete_document(srv, doc.id)
      assert {:error, :not_found} = Documents.update_document(srv, doc.id, %{title: "x"})
    end

    test "cannot set deleted_at through update", %{srv: srv} do
      doc = create(srv)
      {:ok, up} = Documents.update_document(srv, doc.id, %{title: "X", deleted_at: 12345})
      assert up.deleted_at == nil
    end
  end

  describe "soft_delete_document/2" do
    test "sets deleted_at", %{srv: srv} do
      doc = create(srv)
      {:ok, del} = Documents.soft_delete_document(srv, doc.id)
      assert del.deleted_at != nil
    end

    test "no-op on already trashed", %{srv: srv} do
      doc = create(srv)
      {:ok, del} = Documents.soft_delete_document(srv, doc.id)
      {:ok, del2} = Documents.soft_delete_document(srv, doc.id)
      assert del2.deleted_at == del.deleted_at
    end

    test "404 for missing", %{srv: srv} do
      assert {:error, :not_found} = Documents.soft_delete_document(srv, 999)
    end
  end

  describe "restore_document/2 and retention" do
    test "restores a trashed document within window", %{srv: srv} do
      doc = create(srv)
      {:ok, _} = Documents.soft_delete_document(srv, doc.id)
      {:ok, restored} = Documents.restore_document(srv, doc.id)
      assert restored.deleted_at == nil
    end

    test "no-op restoring an active document", %{srv: srv} do
      doc = create(srv)
      assert {:ok, got} = Documents.restore_document(srv, doc.id)
      assert got.deleted_at == nil
    end

    test "expired document cannot be restored", %{srv: srv, advance: advance} do
      doc = create(srv)
      {:ok, _} = Documents.soft_delete_document(srv, doc.id)
      advance.(1000)
      assert {:error, :expired} = Documents.restore_document(srv, doc.id)
      # still visible with include_deleted until purged
      assert {:ok, _} = Documents.get_document(srv, doc.id, include_deleted: true)
    end
  end

  describe "purge" do
    test "purge_document hard-deletes a trashed doc", %{srv: srv} do
      doc = create(srv)
      {:ok, _} = Documents.soft_delete_document(srv, doc.id)
      assert {:ok, _} = Documents.purge_document(srv, doc.id)
      assert {:error, :not_found} = Documents.get_document(srv, doc.id, include_deleted: true)
    end

    test "purge_document refuses an active doc", %{srv: srv} do
      doc = create(srv)
      assert {:error, :not_deleted} = Documents.purge_document(srv, doc.id)
    end

    test "purge_document 404 for missing", %{srv: srv} do
      assert {:error, :not_found} = Documents.purge_document(srv, 999)
    end

    test "purge_expired removes only expired documents", %{srv: srv, advance: advance} do
      a = create(srv, %{title: "keep-active"})
      b = create(srv, %{title: "recent-trash"})
      c = create(srv, %{title: "old-trash"})
      {:ok, _} = Documents.soft_delete_document(srv, c.id)
      advance.(1000)
      {:ok, _} = Documents.soft_delete_document(srv, b.id)

      assert {:ok, 1} = Documents.purge_expired(srv)

      ids = Documents.list_documents(srv, include_deleted: true) |> Enum.map(& &1.id)
      assert a.id in ids
      assert b.id in ids
      refute c.id in ids
    end
  end

  describe "full lifecycle" do
    test "create -> trash -> expire -> purge", %{srv: srv, advance: advance} do
      doc = create(srv, %{title: "Life", content: "v1"})
      {:ok, up} = Documents.update_document(srv, doc.id, %{content: "v2"})
      assert up.content == "v2"

      {:ok, _} = Documents.soft_delete_document(srv, doc.id)
      assert {:error, :not_found} = Documents.get_document(srv, doc.id)

      advance.(1000)
      assert {:error, :expired} = Documents.restore_document(srv, doc.id)

      assert {:ok, 1} = Documents.purge_expired(srv)
      assert {:error, :not_found} = Documents.get_document(srv, doc.id, include_deleted: true)
    end
  end
end
```
