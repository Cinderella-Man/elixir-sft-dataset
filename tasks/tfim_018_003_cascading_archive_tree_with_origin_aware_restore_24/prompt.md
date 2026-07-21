# Fill in the middle: implement the blanked test

Below is a module and its ExUnit test harness with the body of ONE `test` removed
(marked `# TODO`). The test's name states what it must verify. Implement just that one
test so the harness passes for a correct implementation of the module.

## Module under test

```elixir
defmodule CascadeCrud.Archive do
  @moduledoc """
  An in-memory hierarchical archive store implemented as a single `GenServer`.

  The server holds a tree of *nodes*. A node is either a `:folder` (which may
  contain other folders and files) or a `:file` (which always lives inside a
  folder). Nodes are never hard-deleted; instead they are *archived*.

  Archiving is cascading: archiving a folder archives its entire subtree. The
  explicit target of an `archive_node/2` call is recorded with
  `archive_origin: :direct`, while nodes dragged down by an ancestor are marked
  with `archive_origin: :cascade`. Nodes that were already archived when the
  cascade swept over them are left completely untouched.

  Restoring is origin-aware: `unarchive_node/2` only brings back the nodes that
  the corresponding archive operation took down. Descendants whose
  `archive_origin` is `:direct` (they were archived on their own terms) stay in
  the archive together with their whole subtree.

  All state lives in the process; there is no persistence and no ETS. Every
  operation is serialized through the server, so concurrent callers always
  observe a consistent tree.

  ## Node shape

      %{
        id: 1,
        type: :folder,
        name: "reports",
        parent_id: nil,
        content: nil,
        archived_at: nil,
        archive_origin: nil
      }
  """

  use GenServer

  @type id :: pos_integer()
  @type node_type :: :folder | :file
  @type archive_origin :: :direct | :cascade

  @type node_map :: %{
          id: id(),
          type: node_type(),
          name: String.t(),
          parent_id: id() | nil,
          content: String.t() | nil,
          archived_at: DateTime.t() | nil,
          archive_origin: archive_origin() | nil
        }

  @type state :: %{nodes: %{optional(id()) => node_map()}, next_id: pos_integer()}

  # ── Public API ────────────────────────────────────────────────────────────

  @doc """
  Starts the archive server.

  `opts` is a keyword list. When it contains `:name`, the server is registered
  under that name; otherwise it is started unnamed. The module can also be used
  directly as a supervised child, e.g. `{CascadeCrud.Archive, []}`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    case Keyword.fetch(opts, :name) do
      {:ok, name} -> GenServer.start_link(__MODULE__, :ok, name: name)
      :error -> GenServer.start_link(__MODULE__, :ok)
    end
  end

  @doc """
  Creates a folder.

  `attrs` may contain `:name` (required, a non-blank string) and `:parent_id`
  (optional, defaults to `nil` which creates a root folder).
  """
  @spec create_folder(GenServer.server(), map()) ::
          {:ok, node_map()} | {:error, :invalid_name | :parent_not_found | :parent_archived}
  def create_folder(server, attrs) when is_map(attrs) do
    GenServer.call(server, {:create_folder, attrs})
  end

  @doc """
  Creates a file.

  `attrs` may contain `:name` (required), `:parent_id` (required — files always
  live inside a folder) and `:content` (optional string, defaults to `""`).
  """
  @spec create_file(GenServer.server(), map()) ::
          {:ok, node_map()} | {:error, :invalid_name | :parent_not_found | :parent_archived}
  def create_file(server, attrs) when is_map(attrs) do
    GenServer.call(server, {:create_file, attrs})
  end

  @doc """
  Fetches a single node by id.

  Archived nodes are hidden unless `opts` contains `include_archived: true`.
  """
  @spec fetch_node(GenServer.server(), id(), keyword()) ::
          {:ok, node_map()} | {:error, :not_found}
  def fetch_node(server, id, opts \\ []) do
    GenServer.call(server, {:fetch_node, id, include_archived?(opts)})
  end

  @doc """
  Lists the direct children of a folder, sorted by id ascending.

  Archived children are excluded unless `opts` contains `include_archived: true`.
  The folder itself obeys the same visibility rule.
  """
  @spec list_children(GenServer.server(), id(), keyword()) ::
          {:ok, [node_map()]} | {:error, :not_found}
  def list_children(server, folder_id, opts \\ []) do
    GenServer.call(server, {:list_children, folder_id, include_archived?(opts)})
  end

  @doc """
  Renames a live node. Archived nodes cannot be renamed.
  """
  @spec rename_node(GenServer.server(), id(), String.t()) ::
          {:ok, node_map()} | {:error, :invalid_name | :not_found}
  def rename_node(server, id, new_name) do
    GenServer.call(server, {:rename_node, id, new_name})
  end

  @doc """
  Archives a live node, cascading down its subtree when it is a folder.

  Returns `{:ok, %{node: node, cascaded: cascaded_ids}}` where `cascaded_ids`
  are the ids of the descendants archived by *this* call, sorted ascending.
  """
  @spec archive_node(GenServer.server(), id()) ::
          {:ok, %{node: node_map(), cascaded: [id()]}}
          | {:error, :not_found | :already_archived}
  def archive_node(server, id) do
    GenServer.call(server, {:archive_node, id})
  end

  @doc """
  Restores a directly archived node together with the descendants that the same
  cascade took down.

  Descendants with `archive_origin: :direct` stay archived, along with their
  entire subtree.
  """
  @spec unarchive_node(GenServer.server(), id()) ::
          {:ok, %{node: node_map(), restored: [id()]}}
          | {:error, :not_found | :not_archived | :cascade_archived | :parent_archived}
  def unarchive_node(server, id) do
    GenServer.call(server, {:unarchive_node, id})
  end

  @doc """
  Lists every archived node (both `:direct` and `:cascade` origins), sorted by
  id ascending.
  """
  @spec list_archived(GenServer.server()) :: {:ok, [node_map()]}
  def list_archived(server) do
    GenServer.call(server, :list_archived)
  end

  # ── GenServer callbacks ───────────────────────────────────────────────────

  @impl GenServer
  @spec init(:ok) :: {:ok, state()}
  def init(:ok) do
    {:ok, %{nodes: %{}, next_id: 1}}
  end

  @impl GenServer
  def handle_call({:create_folder, attrs}, _from, state) do
    with {:ok, name} <- validate_name(Map.get(attrs, :name)),
         parent_id = Map.get(attrs, :parent_id),
         :ok <- validate_parent(state, parent_id, :optional) do
      do_create(state, %{type: :folder, name: name, parent_id: parent_id, content: nil})
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:create_file, attrs}, _from, state) do
    with {:ok, name} <- validate_name(Map.get(attrs, :name)),
         parent_id = Map.get(attrs, :parent_id),
         :ok <- validate_parent(state, parent_id, :required),
         {:ok, content} <- validate_content(Map.get(attrs, :content, "")) do
      do_create(state, %{type: :file, name: name, parent_id: parent_id, content: content})
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:fetch_node, id, include_archived}, _from, state) do
    case Map.fetch(state.nodes, id) do
      {:ok, node} ->
        if include_archived or live?(node) do
          {:reply, {:ok, node}, state}
        else
          {:reply, {:error, :not_found}, state}
        end

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:list_children, folder_id, include_archived}, _from, state) do
    with {:ok, folder} <- Map.fetch(state.nodes, folder_id),
         true <- folder.type == :folder,
         true <- include_archived or live?(folder) do
      children =
        state.nodes
        |> Map.values()
        |> Enum.filter(fn child ->
          child.parent_id == folder_id and (include_archived or live?(child))
        end)
        |> Enum.sort_by(& &1.id)

      {:reply, {:ok, children}, state}
    else
      _other -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:rename_node, id, new_name}, _from, state) do
    with {:ok, name} <- validate_name(new_name),
         {:ok, node} <- fetch_live(state, id) do
      updated = %{node | name: name}
      {:reply, {:ok, updated}, put_node(state, updated)}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:archive_node, id}, _from, state) do
    case Map.fetch(state.nodes, id) do
      :error ->
        {:reply, {:error, :not_found}, state}

      {:ok, node} ->
        if live?(node) do
          do_archive(state, node)
        else
          {:reply, {:error, :already_archived}, state}
        end
    end
  end

  def handle_call({:unarchive_node, id}, _from, state) do
    with {:ok, node} <- Map.fetch(state.nodes, id),
         :ok <- check_archived(node),
         :ok <- check_direct(node),
         :ok <- check_parent_live(state, node) do
      do_unarchive(state, node)
    else
      :error -> {:reply, {:error, :not_found}, state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call(:list_archived, _from, state) do
    archived =
      state.nodes
      |> Map.values()
      |> Enum.reject(&live?/1)
      |> Enum.sort_by(& &1.id)

    {:reply, {:ok, archived}, state}
  end

  # ── Internal helpers ──────────────────────────────────────────────────────

  defp include_archived?(opts) when is_list(opts) do
    Keyword.get(opts, :include_archived, false) == true
  end

  defp do_create(state, fields) do
    id = state.next_id

    node =
      Map.merge(fields, %{id: id, archived_at: nil, archive_origin: nil})

    new_state = %{state | nodes: Map.put(state.nodes, id, node), next_id: id + 1}
    {:reply, {:ok, node}, new_state}
  end

  defp validate_name(name) when is_binary(name) do
    if String.trim(name) == "" do
      {:error, :invalid_name}
    else
      {:ok, name}
    end
  end

  defp validate_name(_name), do: {:error, :invalid_name}

  defp validate_content(content) when is_binary(content), do: {:ok, content}
  defp validate_content(_content), do: {:ok, ""}

  defp validate_parent(_state, nil, :optional), do: :ok
  defp validate_parent(_state, nil, :required), do: {:error, :parent_not_found}

  defp validate_parent(state, parent_id, _mode) do
    case Map.fetch(state.nodes, parent_id) do
      {:ok, %{type: :folder} = parent} ->
        if live?(parent), do: :ok, else: {:error, :parent_archived}

      _other ->
        {:error, :parent_not_found}
    end
  end

  defp fetch_live(state, id) do
    case Map.fetch(state.nodes, id) do
      {:ok, node} -> if live?(node), do: {:ok, node}, else: {:error, :not_found}
      :error -> {:error, :not_found}
    end
  end

  defp live?(node), do: node.archived_at == nil

  defp put_node(state, node), do: %{state | nodes: Map.put(state.nodes, node.id, node)}

  defp check_archived(node) do
    if live?(node), do: {:error, :not_archived}, else: :ok
  end

  defp check_direct(node) do
    if node.archive_origin == :cascade, do: {:error, :cascade_archived}, else: :ok
  end

  defp check_parent_live(_state, %{parent_id: nil}), do: :ok

  defp check_parent_live(state, node) do
    case Map.fetch(state.nodes, node.parent_id) do
      {:ok, parent} -> if live?(parent), do: :ok, else: {:error, :parent_archived}
      :error -> :ok
    end
  end

  defp do_archive(state, node) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)
    target = %{node | archived_at: now, archive_origin: :direct}
    state = put_node(state, target)

    {state, cascaded} = cascade_archive(state, node.id, now, [])
    {:reply, {:ok, %{node: target, cascaded: Enum.sort(cascaded)}}, state}
  end

  defp cascade_archive(state, parent_id, now, acc) do
    state
    |> children_of(parent_id)
    |> Enum.reduce({state, acc}, fn child, {st, ids} ->
      if live?(child) do
        archived = %{child | archived_at: now, archive_origin: :cascade}
        st = put_node(st, archived)
        cascade_archive(st, child.id, now, [child.id | ids])
      else
        {st, ids}
      end
    end)
  end

  defp do_unarchive(state, node) do
    restored_target = %{node | archived_at: nil, archive_origin: nil}
    state = put_node(state, restored_target)

    {state, restored} = cascade_unarchive(state, node.id, [])
    {:reply, {:ok, %{node: restored_target, restored: Enum.sort(restored)}}, state}
  end

  defp cascade_unarchive(state, parent_id, acc) do
    state
    |> children_of(parent_id)
    |> Enum.reduce({state, acc}, fn child, {st, ids} ->
      if child.archive_origin == :cascade do
        restored = %{child | archived_at: nil, archive_origin: nil}
        st = put_node(st, restored)
        cascade_unarchive(st, child.id, [child.id | ids])
      else
        {st, ids}
      end
    end)
  end

  defp children_of(state, parent_id) do
    state.nodes
    |> Map.values()
    |> Enum.filter(&(&1.parent_id == parent_id))
    |> Enum.sort_by(& &1.id)
  end
end
```

## Test harness — implement the `# TODO` test

```elixir
defmodule CascadeCrud.ArchiveTest do
  use ExUnit.Case, async: false

  alias CascadeCrud.Archive

  setup do
    server = start_supervised!({Archive, []})
    %{server: server}
  end

  # -------------------------------------------------------
  # Helpers
  # -------------------------------------------------------

  defp folder!(server, name, parent_id \\ nil) do
    {:ok, folder} = Archive.create_folder(server, %{name: name, parent_id: parent_id})
    folder
  end

  defp file!(server, name, parent_id, content \\ "body") do
    {:ok, file} =
      Archive.create_file(server, %{name: name, parent_id: parent_id, content: content})

    file
  end

  defp archive!(server, id) do
    {:ok, result} = Archive.archive_node(server, id)
    result
  end

  # -------------------------------------------------------
  # Creation
  # -------------------------------------------------------

  describe "create_folder/2" do
    test "creates a root folder with sequential ids", %{server: s} do
      assert {:ok, a} = Archive.create_folder(s, %{name: "root"})
      assert a.id == 1
      assert a.type == :folder
      assert a.name == "root"
      assert a.parent_id == nil
      assert a.content == nil
      assert a.archived_at == nil
      assert a.archive_origin == nil

      assert {:ok, b} = Archive.create_folder(s, %{name: "other"})
      assert b.id == 2
    end

    test "creates a nested folder", %{server: s} do
      root = folder!(s, "root")
      assert {:ok, child} = Archive.create_folder(s, %{name: "child", parent_id: root.id})
      assert child.parent_id == root.id
    end

    test "rejects invalid names", %{server: s} do
      assert {:error, :invalid_name} = Archive.create_folder(s, %{})
      assert {:error, :invalid_name} = Archive.create_folder(s, %{name: ""})
      assert {:error, :invalid_name} = Archive.create_folder(s, %{name: "   "})
      assert {:error, :invalid_name} = Archive.create_folder(s, %{name: :nope})
    end

    test "rejects a missing or non-folder parent", %{server: s} do
      root = folder!(s, "root")
      f = file!(s, "note.txt", root.id)

      assert {:error, :parent_not_found} =
               Archive.create_folder(s, %{name: "x", parent_id: 999})

      assert {:error, :parent_not_found} =
               Archive.create_folder(s, %{name: "x", parent_id: f.id})
    end

    test "rejects an archived parent", %{server: s} do
      root = folder!(s, "root")
      archive!(s, root.id)

      assert {:error, :parent_archived} =
               Archive.create_folder(s, %{name: "x", parent_id: root.id})
    end
  end

  describe "create_file/2" do
    test "creates a file inside a folder with default content", %{server: s} do
      root = folder!(s, "root")
      assert {:ok, f} = Archive.create_file(s, %{name: "a.txt", parent_id: root.id})
      assert f.type == :file
      assert f.content == ""
      assert f.parent_id == root.id
      assert f.archived_at == nil

      assert {:ok, g} =
               Archive.create_file(s, %{name: "b.txt", parent_id: root.id, content: "hello"})

      assert g.content == "hello"
    end

    test "requires a folder parent", %{server: s} do
      assert {:error, :parent_not_found} = Archive.create_file(s, %{name: "a.txt"})

      assert {:error, :parent_not_found} =
               Archive.create_file(s, %{name: "a.txt", parent_id: nil})

      assert {:error, :parent_not_found} =
               Archive.create_file(s, %{name: "a.txt", parent_id: 42})
    end

    test "rejects an archived parent folder", %{server: s} do
      root = folder!(s, "root")
      archive!(s, root.id)

      assert {:error, :parent_archived} =
               Archive.create_file(s, %{name: "a.txt", parent_id: root.id})
    end

    test "validates the name before the parent", %{server: s} do
      assert {:error, :invalid_name} = Archive.create_file(s, %{name: "", parent_id: 999})
    end
  end

  # -------------------------------------------------------
  # Fetch / list
  # -------------------------------------------------------

  describe "fetch_node/3" do
    test "fetches a live node", %{server: s} do
      root = folder!(s, "root")
      assert {:ok, fetched} = Archive.fetch_node(s, root.id)
      assert fetched.id == root.id
      assert fetched.name == "root"
    end

    test "returns :not_found for unknown ids", %{server: s} do
      assert {:error, :not_found} = Archive.fetch_node(s, 123)
    end

    test "hides archived nodes unless include_archived: true", %{server: s} do
      root = folder!(s, "root")
      archive!(s, root.id)

      assert {:error, :not_found} = Archive.fetch_node(s, root.id)
      assert {:ok, node} = Archive.fetch_node(s, root.id, include_archived: true)
      assert node.archive_origin == :direct
      assert %DateTime{} = node.archived_at
    end
  end

  describe "list_children/3" do
    test "returns direct children sorted by id, excluding archived by default", %{server: s} do
      root = folder!(s, "root")
      a = file!(s, "a.txt", root.id)
      sub = folder!(s, "sub", root.id)
      b = file!(s, "b.txt", root.id)
      _deep = file!(s, "deep.txt", sub.id)

      archive!(s, a.id)

      assert {:ok, children} = Archive.list_children(s, root.id)
      assert Enum.map(children, & &1.id) == [sub.id, b.id]

      assert {:ok, all} = Archive.list_children(s, root.id, include_archived: true)
      assert Enum.map(all, & &1.id) == Enum.sort([a.id, sub.id, b.id])
    end

    test "empty folder yields an empty list", %{server: s} do
      root = folder!(s, "root")
      assert {:ok, []} = Archive.list_children(s, root.id)
    end

    test "archived folder is hidden unless include_archived: true", %{server: s} do
      root = folder!(s, "root")
      child = file!(s, "a.txt", root.id)
      archive!(s, root.id)

      assert {:error, :not_found} = Archive.list_children(s, root.id)

      assert {:ok, children} = Archive.list_children(s, root.id, include_archived: true)
      assert Enum.map(children, & &1.id) == [child.id]
    end

    test "returns :not_found for files and unknown ids", %{server: s} do
      root = folder!(s, "root")
      f = file!(s, "a.txt", root.id)

      assert {:error, :not_found} = Archive.list_children(s, f.id)
      assert {:error, :not_found} = Archive.list_children(s, 999)
    end
  end

  # -------------------------------------------------------
  # Rename
  # -------------------------------------------------------

  describe "rename_node/3" do
    test "renames a live folder and file", %{server: s} do
      root = folder!(s, "root")
      f = file!(s, "a.txt", root.id)

      assert {:ok, renamed} = Archive.rename_node(s, root.id, "archive")
      assert renamed.name == "archive"
      assert {:ok, again} = Archive.fetch_node(s, root.id)
      assert again.name == "archive"

      assert {:ok, rf} = Archive.rename_node(s, f.id, "b.txt")
      assert rf.name == "b.txt"
      assert rf.content == "body"
    end

    test "rejects invalid names", %{server: s} do
      root = folder!(s, "root")
      assert {:error, :invalid_name} = Archive.rename_node(s, root.id, "")
      assert {:error, :invalid_name} = Archive.rename_node(s, root.id, "  ")
      assert {:error, :invalid_name} = Archive.rename_node(s, root.id, 7)
    end

    test "cannot rename archived or unknown nodes", %{server: s} do
      root = folder!(s, "root")
      archive!(s, root.id)

      assert {:error, :not_found} = Archive.rename_node(s, root.id, "nope")
      assert {:error, :not_found} = Archive.rename_node(s, 999, "nope")
    end
  end

  # -------------------------------------------------------
  # Cascading archive
  # -------------------------------------------------------

  describe "archive_node/2" do
    test "archiving a file affects only that file", %{server: s} do
      root = folder!(s, "root")
      f = file!(s, "a.txt", root.id)

      assert {:ok, %{node: node, cascaded: []}} = Archive.archive_node(s, f.id)
      assert node.id == f.id
      assert node.archive_origin == :direct
      assert %DateTime{} = node.archived_at

      assert {:ok, _} = Archive.fetch_node(s, root.id)
      assert {:error, :not_found} = Archive.fetch_node(s, f.id)
    end

    test "archiving a folder cascades to the whole subtree with one timestamp", %{server: s} do
      root = folder!(s, "root")
      sub = folder!(s, "sub", root.id)
      a = file!(s, "a.txt", root.id)
      b = file!(s, "b.txt", sub.id)

      assert {:ok, %{node: node, cascaded: cascaded}} = Archive.archive_node(s, root.id)
      assert node.archive_origin == :direct
      assert cascaded == Enum.sort([sub.id, a.id, b.id])

      for id <- cascaded do
        assert {:ok, n} = Archive.fetch_node(s, id, include_archived: true)
        assert n.archive_origin == :cascade
        assert n.archived_at == node.archived_at
        assert {:error, :not_found} = Archive.fetch_node(s, id)
      end
    end

    test "already-archived descendants are left untouched and not reported", %{server: s} do
      root = folder!(s, "root")
      sub = folder!(s, "sub", root.id)
      deep = file!(s, "deep.txt", sub.id)
      loose = file!(s, "loose.txt", root.id)

      %{node: sub_archived} = archive!(s, sub.id)
      assert {:ok, %{cascaded: cascaded}} = Archive.archive_node(s, root.id)

      assert cascaded == [loose.id]

      assert {:ok, sub_now} = Archive.fetch_node(s, sub.id, include_archived: true)
      assert sub_now.archive_origin == :direct
      assert sub_now.archived_at == sub_archived.archived_at

      assert {:ok, deep_now} = Archive.fetch_node(s, deep.id, include_archived: true)
      assert deep_now.archive_origin == :cascade
    end

    test "errors for unknown and already-archived nodes", %{server: s} do
      # TODO
    end
  end

  # -------------------------------------------------------
  # Archive timestamp shape
  # -------------------------------------------------------

  describe "archived_at shape" do
    test "the returned target timestamp is UTC and truncated to the second", %{server: s} do
      root = folder!(s, "root")

      assert {:ok, %{node: node}} = Archive.archive_node(s, root.id)
      assert %DateTime{} = ts = node.archived_at

      # UTC zone: no offset from UTC, and the UTC zone name.
      assert ts.time_zone == "Etc/UTC"
      assert ts.utc_offset == 0
      assert ts.std_offset == 0

      # Second precision: no sub-second component survives truncation.
      assert ts.microsecond == {0, 0}
      assert DateTime.truncate(ts, :second) == ts
    end

    test "stored timestamps on target and cascade are UTC second-precision", %{server: s} do
      root = folder!(s, "root")
      sub = folder!(s, "sub", root.id)
      leaf = file!(s, "a.txt", sub.id)

      archive!(s, root.id)

      for id <- [root.id, sub.id, leaf.id] do
        assert {:ok, stored} = Archive.fetch_node(s, id, include_archived: true)
        assert %DateTime{} = ts = stored.archived_at
        assert ts.time_zone == "Etc/UTC"
        assert ts.utc_offset == 0
        assert ts.std_offset == 0
        assert ts.microsecond == {0, 0}
        assert DateTime.truncate(ts, :second) == ts
      end
    end

    test "a directly archived file also carries a UTC second-precision stamp", %{server: s} do
      root = folder!(s, "root")
      f = file!(s, "a.txt", root.id)

      assert {:ok, %{node: node, cascaded: []}} = Archive.archive_node(s, f.id)
      assert %DateTime{} = ts = node.archived_at
      assert ts.time_zone == "Etc/UTC"
      assert ts.microsecond == {0, 0}
      assert DateTime.truncate(ts, :second) == ts

      assert {:ok, listed} = Archive.list_archived(s)
      assert [only] = listed
      assert only.id == f.id
      assert only.archived_at == ts
    end
  end

  # -------------------------------------------------------
  # Origin-aware restore
  # -------------------------------------------------------

  describe "unarchive_node/2" do
    test "restores a directly archived node and its cascade", %{server: s} do
      root = folder!(s, "root")
      sub = folder!(s, "sub", root.id)
      a = file!(s, "a.txt", sub.id)

      archive!(s, root.id)

      assert {:ok, %{node: node, restored: restored}} = Archive.unarchive_node(s, root.id)
      assert node.archived_at == nil
      assert node.archive_origin == nil
      assert restored == Enum.sort([sub.id, a.id])

      for id <- [root.id, sub.id, a.id] do
        assert {:ok, n} = Archive.fetch_node(s, id)
        assert n.archived_at == nil
        assert n.archive_origin == nil
      end

      assert {:ok, []} = Archive.list_archived(s)
    end

    test "a directly archived child stays archived when the parent is restored", %{server: s} do
      root = folder!(s, "root")
      sub = folder!(s, "sub", root.id)
      deep = file!(s, "deep.txt", sub.id)
      loose = file!(s, "loose.txt", root.id)

      archive!(s, sub.id)
      archive!(s, root.id)

      assert {:ok, %{restored: restored}} = Archive.unarchive_node(s, root.id)
      assert restored == [loose.id]

      assert {:ok, _} = Archive.fetch_node(s, loose.id)
      assert {:error, :not_found} = Archive.fetch_node(s, sub.id)
      assert {:error, :not_found} = Archive.fetch_node(s, deep.id)

      assert {:ok, archived} = Archive.list_archived(s)
      assert Enum.map(archived, & &1.id) == Enum.sort([sub.id, deep.id])
    end

    test "a cascade-archived node cannot be restored on its own", %{server: s} do
      root = folder!(s, "root")
      a = file!(s, "a.txt", root.id)
      archive!(s, root.id)

      assert {:error, :cascade_archived} = Archive.unarchive_node(s, a.id)
      assert {:error, :not_found} = Archive.fetch_node(s, a.id)
    end

    test "cannot restore while the parent is still archived", %{server: s} do
      root = folder!(s, "root")
      sub = folder!(s, "sub", root.id)

      archive!(s, sub.id)
      archive!(s, root.id)

      assert {:error, :parent_archived} = Archive.unarchive_node(s, sub.id)

      assert {:ok, _} = Archive.unarchive_node(s, root.id)
      assert {:ok, %{node: node}} = Archive.unarchive_node(s, sub.id)
      assert node.archived_at == nil
    end

    test "errors for live and unknown nodes", %{server: s} do
      root = folder!(s, "root")

      assert {:error, :not_archived} = Archive.unarchive_node(s, root.id)
      assert {:error, :not_found} = Archive.unarchive_node(s, 999)
    end
  end

  # -------------------------------------------------------
  # Archived listing
  # -------------------------------------------------------

  describe "list_archived/1" do
    test "starts empty and lists every archived node sorted by id", %{server: s} do
      assert {:ok, []} = Archive.list_archived(s)

      root = folder!(s, "root")
      sub = folder!(s, "sub", root.id)
      a = file!(s, "a.txt", sub.id)
      keep = folder!(s, "keep")

      archive!(s, root.id)

      assert {:ok, archived} = Archive.list_archived(s)
      assert Enum.map(archived, & &1.id) == Enum.sort([root.id, sub.id, a.id])
      refute keep.id in Enum.map(archived, & &1.id)

      origins = Map.new(archived, &{&1.id, &1.archive_origin})
      assert origins[root.id] == :direct
      assert origins[sub.id] == :cascade
      assert origins[a.id] == :cascade
    end
  end

  # -------------------------------------------------------
  # Lifecycle
  # -------------------------------------------------------

  describe "full lifecycle" do
    test "build → archive → hidden → restore → visible → re-archive", %{server: s} do
      root = folder!(s, "projects")
      sub = folder!(s, "2026", root.id)
      note = file!(s, "notes.md", sub.id, "v1")

      assert {:ok, renamed} = Archive.rename_node(s, note.id, "notes.txt")
      assert renamed.name == "notes.txt"

      assert {:ok, %{cascaded: cascaded}} = Archive.archive_node(s, root.id)
      assert cascaded == Enum.sort([sub.id, note.id])
      assert {:error, :not_found} = Archive.fetch_node(s, note.id)
      assert {:error, :parent_archived} = Archive.create_file(s, %{name: "x", parent_id: sub.id})

      assert {:ok, %{restored: restored}} = Archive.unarchive_node(s, root.id)
      assert restored == Enum.sort([sub.id, note.id])
      assert {:ok, back} = Archive.fetch_node(s, note.id)
      assert back.name == "notes.txt"
      assert back.content == "v1"

      assert {:ok, %{cascaded: again}} = Archive.archive_node(s, sub.id)
      assert again == [note.id]
      assert {:ok, children} = Archive.list_children(s, root.id)
      assert children == []
    end

    test "ids are never reused across archive and restore", %{server: s} do
      a = folder!(s, "a")
      archive!(s, a.id)
      b = folder!(s, "b")
      assert b.id == a.id + 1

      assert {:ok, _} = Archive.unarchive_node(s, a.id)
      c = folder!(s, "c")
      assert c.id == b.id + 1
    end
  end

  test "restore walks through a cascade child but skips a direct grandchild subtree", %{server: s} do
    root = folder!(s, "root")
    mid = folder!(s, "mid", root.id)
    leaf = folder!(s, "leaf", mid.id)
    deep = file!(s, "deep.txt", leaf.id)

    %{node: leaf_archived} = archive!(s, leaf.id)
    assert {:ok, %{cascaded: cascaded}} = Archive.archive_node(s, root.id)
    assert cascaded == [mid.id]

    assert {:ok, %{restored: restored}} = Archive.unarchive_node(s, root.id)
    assert restored == [mid.id]

    assert {:ok, _} = Archive.fetch_node(s, mid.id)
    assert {:error, :not_found} = Archive.fetch_node(s, leaf.id)

    assert {:ok, leaf_now} = Archive.fetch_node(s, leaf.id, include_archived: true)
    assert leaf_now.archive_origin == :direct
    assert leaf_now.archived_at == leaf_archived.archived_at

    assert {:ok, deep_now} = Archive.fetch_node(s, deep.id, include_archived: true)
    assert deep_now.archive_origin == :cascade

    assert {:ok, %{restored: leaf_restored}} = Archive.unarchive_node(s, leaf.id)
    assert leaf_restored == [deep.id]
    assert {:ok, []} = Archive.list_archived(s)
  end

  test "start_link registers the server under the given :name and serves calls through it" do
    name = :"cascade_archive_named_#{System.unique_integer([:positive])}"

    assert {:ok, pid} = Archive.start_link(name: name)
    assert Process.whereis(name) == pid

    assert {:ok, folder} = Archive.create_folder(name, %{name: "root"})
    assert folder.id == 1
    assert {:ok, ^folder} = Archive.fetch_node(name, folder.id)

    assert {:ok, %{node: node, cascaded: []}} = Archive.archive_node(name, folder.id)
    assert node.archive_origin == :direct
    assert {:ok, [archived]} = Archive.list_archived(name)
    assert archived.id == folder.id
  end

  test "rename_node reports :invalid_name before the node lookup", %{server: s} do
    assert {:error, :invalid_name} = Archive.rename_node(s, 999, "")
    assert {:error, :invalid_name} = Archive.rename_node(s, 999, "   ")
    assert {:error, :invalid_name} = Archive.rename_node(s, 999, :nope)

    root = folder!(s, "root")
    archive!(s, root.id)
    assert {:error, :invalid_name} = Archive.rename_node(s, root.id, "  ")
  end

  test "archiving a cascade-archived descendant reports :already_archived and restamps nothing",
       %{
         server: s
       } do
    root = folder!(s, "root")
    sub = folder!(s, "sub", root.id)
    f = file!(s, "a.txt", sub.id)

    %{node: target} = archive!(s, root.id)

    assert {:error, :already_archived} = Archive.archive_node(s, sub.id)
    assert {:error, :already_archived} = Archive.archive_node(s, f.id)

    for id <- [sub.id, f.id] do
      assert {:ok, n} = Archive.fetch_node(s, id, include_archived: true)
      assert n.archive_origin == :cascade
      assert n.archived_at == target.archived_at
    end
  end

  test "an archived file used as a parent yields :parent_not_found", %{server: s} do
    root = folder!(s, "root")
    f = file!(s, "a.txt", root.id)
    archive!(s, f.id)

    assert {:error, :parent_not_found} =
             Archive.create_file(s, %{name: "b.txt", parent_id: f.id})

    assert {:error, :parent_not_found} =
             Archive.create_folder(s, %{name: "sub", parent_id: f.id})
  end

  # -------------------------------------------------------
  # Timestamp precision seen through every archived view
  # -------------------------------------------------------

  # A stamp must be a UTC DateTime with no sub-second component left.
  defp assert_utc_second_precision(stamp) do
    assert %DateTime{} = stamp
    assert stamp.time_zone == "Etc/UTC"
    assert stamp.utc_offset == 0
    assert stamp.std_offset == 0
    assert stamp.microsecond == {0, 0}
    assert DateTime.truncate(stamp, :second) == stamp
  end

  test "list_archived stamps are UTC second-precision for both origins", %{server: s} do
    root = folder!(s, "root")
    sub = folder!(s, "sub", root.id)
    leaf = file!(s, "a.txt", sub.id)
    other = folder!(s, "other")

    %{node: root_target} = archive!(s, root.id)
    %{node: other_target} = archive!(s, other.id)

    assert {:ok, archived} = Archive.list_archived(s)
    assert Enum.map(archived, & &1.id) == Enum.sort([root.id, sub.id, leaf.id, other.id])

    for node <- archived do
      assert_utc_second_precision(node.archived_at)
    end

    stamps = Map.new(archived, &{&1.id, &1.archived_at})
    assert stamps[root.id] == root_target.archived_at
    assert stamps[sub.id] == root_target.archived_at
    assert stamps[leaf.id] == root_target.archived_at
    assert stamps[other.id] == other_target.archived_at
  end

  test "re-archiving stamps UTC second-precision seen via list_children", %{server: s} do
    root = folder!(s, "root")
    sub = folder!(s, "sub", root.id)
    f = file!(s, "a.txt", sub.id)

    archive!(s, root.id)
    assert {:ok, _} = Archive.unarchive_node(s, root.id)

    assert {:ok, %{node: node, cascaded: [_ | _]}} = Archive.archive_node(s, sub.id)
    assert_utc_second_precision(node.archived_at)

    assert {:ok, children} = Archive.list_children(s, sub.id, include_archived: true)
    assert [child] = children
    assert child.id == f.id
    assert_utc_second_precision(child.archived_at)
    assert child.archived_at == node.archived_at
  end
end
```
