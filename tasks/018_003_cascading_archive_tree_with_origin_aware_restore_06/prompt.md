# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `create_folder` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

Build me an in-memory **hierarchical archive store** as a single Elixir GenServer module named `CascadeCrud.Archive`. There is no database, no Phoenix, and no supervision tree to build — just this one module. It stores a tree of *nodes* (folders and files) and supports **cascading archive** (soft delete that propagates down a subtree) and **origin-aware restore** (an un-archive only brings back what *that* archive operation took down).

## Node shape

Every node is a plain map with exactly these keys:

```elixir
%{
  id: 1,                   # positive integer, assigned by the server
  type: :folder,           # :folder or :file
  name: "reports",         # non-empty string
  parent_id: nil,          # id of the containing folder, or nil for a root folder
  content: nil,            # string for files, nil for folders
  archived_at: nil,        # nil when live, a DateTime when archived
  archive_origin: nil      # nil when live, :direct or :cascade when archived
}
```

- IDs are assigned sequentially starting at `1`, in creation order, and are never reused.
- `archived_at` is a `DateTime` in UTC truncated to the second.
- `archive_origin` is `:direct` when the node was the explicit target of an archive call, and `:cascade` when it was archived only because an ancestor was archived.

Attribute maps passed into the API use **atom keys**.

## Public API

### `start_link(opts)`

Starts the server. `opts` is a keyword list; if it contains `:name`, the server is registered under that name, otherwise it is started unnamed. Returns `{:ok, pid}`. The module must also be usable as a supervised child (i.e. `start_supervised!({CascadeCrud.Archive, []})` must work).

Every other function takes the server (pid or registered name) as its first argument.

### `create_folder(server, attrs)`

`attrs` may contain `:name` (required) and `:parent_id` (optional, defaults to `nil` meaning a root folder).

- `{:ok, folder}` on success (a node map with `type: :folder`, `content: nil`, `archived_at: nil`, `archive_origin: nil`).
- `{:error, :invalid_name}` if `:name` is missing, is not a string, or is empty / whitespace-only.
- `{:error, :parent_not_found}` if `:parent_id` is given but no node with that id exists, or that node is a file.
- `{:error, :parent_archived}` if the parent folder exists but is archived.

### `create_file(server, attrs)`

`attrs` may contain `:name` (required), `:parent_id` (**required** — files always live inside a folder) and `:content` (optional string, defaults to `""`).

- `{:ok, file}` on success (`type: :file`, `content` set).
- `{:error, :invalid_name}` — same name rules as above.
- `{:error, :parent_not_found}` if `:parent_id` is `nil`/missing, refers to no node, or refers to a file.
- `{:error, :parent_archived}` if the parent folder is archived.

Validation order: the name is validated before the parent.

### `fetch_node(server, id, opts \\ [])`

- `{:ok, node}` if a node with that id exists and is live.
- If the node is archived: `{:error, :not_found}` by default, but `{:ok, node}` when `opts` contains `include_archived: true`.
- `{:error, :not_found}` if no node has that id.

### `list_children(server, folder_id, opts \\ [])`

Direct children of the given folder (not the whole subtree), **sorted by id ascending**.

- `{:ok, children}` — archived children are excluded unless `opts` contains `include_archived: true`.
- The folder itself is subject to the same visibility rule: if it is archived and `include_archived: true` is not given, return `{:error, :not_found}`.
- `{:error, :not_found}` if no node has that id, or the id refers to a file.
- An empty folder yields `{:ok, []}`.

### `rename_node(server, id, new_name)`

Renames a **live** node (folder or file).

- `{:ok, node}` with the updated name.
- `{:error, :invalid_name}` if `new_name` is not a non-empty (non-whitespace-only) string.
- `{:error, :not_found}` if no node has that id **or the node is archived** (archived nodes cannot be renamed).

Validation order: the name is validated before the node lookup.

### `archive_node(server, id)`

Archives a live node. If it is a folder, its entire subtree is archived too.

- `{:ok, %{node: node, cascaded: cascaded_ids}}` where:
  - `node` is the target with `archive_origin: :direct` and `archived_at` set,
  - `cascaded_ids` is the list of ids of the descendants that this call archived, **sorted ascending**. Those descendants get `archive_origin: :cascade` and **the same `archived_at` value as the target**.
  - Descendants that were *already* archived before this call are left completely untouched (their `archived_at` and `archive_origin` do not change) and their ids do **not** appear in `cascaded_ids`.
- `{:error, :already_archived}` if the node exists but is already archived.
- `{:error, :not_found}` if no node has that id.

Archiving a file archives just that file (`cascaded: []`).

### `unarchive_node(server, id)`

Restores a node that was archived **directly**, together with the descendants that were taken down by that same cascade.

- `{:ok, %{node: node, restored: restored_ids}}` where `node` is the target back to `archived_at: nil, archive_origin: nil`, and `restored_ids` are the ids of descendants restored by this call, sorted ascending.
- Restoration walks down from the target: a child with `archive_origin: :cascade` is restored and the walk continues through it; a child with `archive_origin: :direct` is **left archived and its whole subtree is skipped** (it was archived on its own terms, so it stays in the archive).
- `{:error, :not_found}` if no node has that id.
- `{:error, :not_archived}` if the node exists and is live.
- `{:error, :cascade_archived}` if the node's `archive_origin` is `:cascade` — a cascade-archived node can only come back by restoring the ancestor that took it down.
- `{:error, :parent_archived}` if the node's parent folder is still archived (this can happen when a child was archived directly and then its parent was archived directly afterwards).

### `list_archived(server)`

Returns `{:ok, nodes}` — every archived node (both `:direct` and `:cascade` origins), sorted by id ascending.

## Notes

- All state lives in the GenServer; no persistence, no ETS.
- All operations are serialized through the server, so concurrent callers see a consistent tree.
- Compile with zero warnings.

## The module with `create_folder` missing

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
    # TODO
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

Give me only the complete implementation of `create_folder` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
