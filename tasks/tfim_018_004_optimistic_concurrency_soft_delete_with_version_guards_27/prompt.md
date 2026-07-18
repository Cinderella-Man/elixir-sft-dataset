# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

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

  @doc false
  @impl true
  @spec init(keyword()) :: {:ok, map()}
  def init(_opts), do: {:ok, %{docs: %{}, next_id: 1, tick: 1}}

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

## Test harness — implement the `# TODO` test

```elixir
defmodule SoftCrud.DocumentsTest do
  use ExUnit.Case, async: false

  alias SoftCrud.Documents

  setup do
    {:ok, srv} = Documents.start_link()
    {:ok, srv: srv}
  end

  defp create(srv, attrs \\ %{}) do
    {:ok, doc} = Documents.create_document(srv, Map.merge(%{title: "T", content: "C"}, attrs))
    doc
  end

  describe "create_document/2" do
    test "creates with version 0", %{srv: srv} do
      {:ok, doc} = Documents.create_document(srv, %{title: "A", content: "B"})
      assert doc.lock_version == 0
      assert doc.deleted_at == nil
    end

    test "rejects blank fields", %{srv: srv} do
      assert {:error, e} = Documents.create_document(srv, %{title: "", content: "B"})
      assert e[:title]
    end
  end

  describe "get/list visibility" do
    test "hides soft-deleted by default", %{srv: srv} do
      doc = create(srv)
      {:ok, _} = Documents.soft_delete_document(srv, doc.id, 0)
      assert {:error, :not_found} = Documents.get_document(srv, doc.id)
      assert {:ok, _} = Documents.get_document(srv, doc.id, include_deleted: true)
    end

    test "list excludes deleted by default", %{srv: srv} do
      a = create(srv, %{title: "keep"})
      b = create(srv, %{title: "gone"})
      {:ok, _} = Documents.soft_delete_document(srv, b.id, 0)
      ids = Documents.list_documents(srv) |> Enum.map(& &1.id)
      assert a.id in ids
      refute b.id in ids
    end
  end

  describe "update_document/4 with version guard" do
    test "succeeds with matching version and bumps it", %{srv: srv} do
      doc = create(srv, %{title: "old"})
      {:ok, up} = Documents.update_document(srv, doc.id, %{title: "new"}, 0)
      assert up.title == "new"
      assert up.lock_version == 1
    end

    test "partial update keeps other field", %{srv: srv} do
      doc = create(srv, %{title: "old", content: "keep"})
      {:ok, up} = Documents.update_document(srv, doc.id, %{title: "new"}, 0)
      assert up.content == "keep"
    end

    test "stale version is rejected", %{srv: srv} do
      doc = create(srv)
      {:ok, _} = Documents.update_document(srv, doc.id, %{title: "v1"}, 0)

      assert {:error, :stale_version, 1} =
               Documents.update_document(srv, doc.id, %{title: "v2"}, 0)
    end

    test "invalid attrs rejected after version check", %{srv: srv} do
      doc = create(srv)
      assert {:error, e} = Documents.update_document(srv, doc.id, %{title: ""}, 0)
      assert e[:title]
    end

    test "404 for missing and for soft-deleted", %{srv: srv} do
      assert {:error, :not_found} = Documents.update_document(srv, 999, %{title: "x"}, 0)
      doc = create(srv)
      {:ok, _} = Documents.soft_delete_document(srv, doc.id, 0)
      assert {:error, :not_found} = Documents.update_document(srv, doc.id, %{title: "x"}, 1)
    end

    test "cannot set deleted_at via update", %{srv: srv} do
      doc = create(srv)
      {:ok, up} = Documents.update_document(srv, doc.id, %{title: "X", deleted_at: 99}, 0)
      assert up.deleted_at == nil
    end
  end

  describe "soft_delete_document/3" do
    test "deletes with matching version", %{srv: srv} do
      doc = create(srv)
      {:ok, del} = Documents.soft_delete_document(srv, doc.id, 0)
      assert del.deleted_at != nil
      assert del.lock_version == 1
    end

    test "stale version rejected", %{srv: srv} do
      doc = create(srv)
      {:ok, _} = Documents.update_document(srv, doc.id, %{title: "v"}, 0)
      assert {:error, :stale_version, 1} = Documents.soft_delete_document(srv, doc.id, 0)
    end

    test "already deleted rejected", %{srv: srv} do
      doc = create(srv)
      {:ok, del} = Documents.soft_delete_document(srv, doc.id, 0)

      assert {:error, :already_deleted} =
               Documents.soft_delete_document(srv, doc.id, del.lock_version)
    end

    test "404 for missing", %{srv: srv} do
      assert {:error, :not_found} = Documents.soft_delete_document(srv, 999, 0)
    end
  end

  describe "restore_document/3" do
    test "restores with matching version", %{srv: srv} do
      doc = create(srv)
      {:ok, del} = Documents.soft_delete_document(srv, doc.id, 0)
      {:ok, res} = Documents.restore_document(srv, doc.id, del.lock_version)
      assert res.deleted_at == nil
      assert res.lock_version == 2
    end

    test "stale version rejected", %{srv: srv} do
      doc = create(srv)
      {:ok, _} = Documents.soft_delete_document(srv, doc.id, 0)
      assert {:error, :stale_version, 1} = Documents.restore_document(srv, doc.id, 0)
    end

    test "not-deleted rejected", %{srv: srv} do
      doc = create(srv)
      assert {:error, :not_deleted} = Documents.restore_document(srv, doc.id, 0)
    end

    test "404 for missing", %{srv: srv} do
      assert {:error, :not_found} = Documents.restore_document(srv, 999, 0)
    end
  end

  describe "concurrency" do
    test "concurrent soft-deletes with same expected version: exactly one wins", %{srv: srv} do
      doc = create(srv)

      results =
        1..50
        |> Enum.map(fn _ ->
          Task.async(fn -> Documents.soft_delete_document(srv, doc.id, 0) end)
        end)
        |> Enum.map(&Task.await/1)

      oks = Enum.count(results, &match?({:ok, _}, &1))
      stale = Enum.count(results, &match?({:error, :stale_version, 1}, &1))

      assert oks == 1
      assert stale == 49

      {:ok, d} = Documents.get_document(srv, doc.id, include_deleted: true)
      assert d.lock_version == 1
      assert d.deleted_at != nil
    end

    test "concurrent updates with same expected version: exactly one wins", %{srv: srv} do
      doc = create(srv)

      results =
        1..30
        |> Enum.map(fn i ->
          Task.async(fn -> Documents.update_document(srv, doc.id, %{title: "t#{i}"}, 0) end)
        end)
        |> Enum.map(&Task.await/1)

      assert Enum.count(results, &match?({:ok, _}, &1)) == 1
      assert Enum.count(results, &match?({:error, :stale_version, 1}, &1)) == 29
    end
  end

  describe "full lifecycle" do
    test "create -> update -> delete -> restore threading versions", %{srv: srv} do
      doc = create(srv, %{title: "Life", content: "v1"})
      {:ok, a} = Documents.update_document(srv, doc.id, %{content: "v2"}, doc.lock_version)
      {:ok, b} = Documents.soft_delete_document(srv, doc.id, a.lock_version)
      assert b.deleted_at != nil
      {:ok, c} = Documents.restore_document(srv, doc.id, b.lock_version)
      assert c.deleted_at == nil
      assert c.content == "v2"
      assert c.lock_version == 3
    end
  end

  test "string-keyed attrs are accepted by create and update", %{srv: srv} do
    assert {:ok, doc} = Documents.create_document(srv, %{"title" => "S", "content" => "C"})
    assert doc.title == "S"
    assert doc.content == "C"
    assert doc.lock_version == 0

    assert {:ok, up} = Documents.update_document(srv, doc.id, %{"content" => "C2"}, 0)
    assert up.content == "C2"
    assert up.title == "S"
    assert up.lock_version == 1
  end

  test "list with include_deleted: true returns every document sorted by id", %{srv: srv} do
    a = create(srv, %{title: "a"})
    b = create(srv, %{title: "b"})
    c = create(srv, %{title: "c"})
    {:ok, _} = Documents.soft_delete_document(srv, b.id, 0)

    ids =
      srv
      |> Documents.list_documents(include_deleted: true)
      |> Enum.map(& &1.id)

    assert ids == [a.id, b.id, c.id]
    assert ids == Enum.sort(ids)
  end

  test "soft delete of a deleted doc with a stale version reports stale first", %{srv: srv} do
    doc = create(srv)
    {:ok, _} = Documents.soft_delete_document(srv, doc.id, 0)

    assert {:error, :stale_version, 1} = Documents.soft_delete_document(srv, doc.id, 0)
  end

  test "update of a soft-deleted doc reports not_found even when version is stale", %{srv: srv} do
    doc = create(srv)
    {:ok, _} = Documents.soft_delete_document(srv, doc.id, 0)

    assert {:error, :not_found} = Documents.update_document(srv, doc.id, %{title: "x"}, 0)
  end

  test "create rejects blank content and stores nothing", %{srv: srv} do
    # TODO
  end

  test "rejected stale update leaves the stored document untouched", %{srv: srv} do
    doc = create(srv, %{title: "keep", content: "same"})
    {:ok, _} = Documents.update_document(srv, doc.id, %{title: "v1"}, 0)

    assert {:error, :stale_version, 1} =
             Documents.update_document(srv, doc.id, %{title: "v2", content: "other"}, 0)

    assert {:ok, cur} = Documents.get_document(srv, doc.id)
    assert cur.title == "v1"
    assert cur.content == "same"
    assert cur.lock_version == 1
  end
end
```
