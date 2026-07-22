defmodule CascadeCrud.Archive do
  @moduledoc """
  An in-memory hierarchical archive store implemented as a single `GenServer`.

  The server holds a tree of *nodes*. A node is either a `:folder` (which may contain other
  nodes) or a `:file` (which always lives inside a folder). Every node is a plain map:

      %{
        id: 1,
        type: :folder,
        name: "reports",
        parent_id: nil,
        content: nil,
        archived_at: nil,
        archive_origin: nil
      }

  Ids are positive integers assigned sequentially from `1` in creation order and are never
  reused.

  ## Archiving

  Archiving is a soft delete. `archive_node/2` stamps the target with the current UTC
  `DateTime` (truncated to the second) and `archive_origin: :direct`, then cascades down the
  whole subtree, stamping every *live* descendant with the very same `archived_at` and
  `archive_origin: :cascade`. Descendants that were already archived beforehand keep their own
  timestamp and origin and are skipped entirely (together with their subtrees).

  ## Restoring

  `unarchive_node/2` is origin aware: it only brings back what the matching archive operation
  took down. Restoration walks from the target through children whose origin is `:cascade`;
  a child archived directly (origin `:direct`) stays archived, and its subtree is skipped.
  A node archived by a cascade cannot be restored on its own — the ancestor that took it down
  must be restored instead.

  All state lives in the process; there is no persistence and no ETS. Because every operation
  is a `GenServer.call/2`, concurrent callers always observe a consistent tree.
  """

  use GenServer

  @type id :: pos_integer()
  @type node_type :: :folder | :file
  @type origin :: :direct | :cascade

  @type node_map :: %{
          id: id(),
          type: node_type(),
          name: String.t(),
          parent_id: id() | nil,
          content: String.t() | nil,
          archived_at: DateTime.t() | nil,
          archive_origin: origin() | nil
        }

  @type state :: %{nodes: %{optional(id()) => node_map()}, next_id: id()}

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the archive server.

  `opts` is a keyword list. When it contains `:name`, the server is registered under that
  name; otherwise it is started unnamed. Usable directly as a supervised child, e.g.
  `{CascadeCrud.Archive, name: MyArchive}`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    case Keyword.get(opts, :name) do
      nil -> GenServer.start_link(__MODULE__, :ok, [])
      name -> GenServer.start_link(__MODULE__, :ok, name: name)
    end
  end

  @doc """
  Creates a folder.

  `attrs` accepts `:name` (required, non-empty string) and `:parent_id` (optional, `nil` means
  a root folder).

  Returns `{:ok, folder}`, `{:error, :invalid_name}`, `{:error, :parent_not_found}` or
  `{:error, :parent_archived}`.
  """
  @spec create_folder(GenServer.server(), map()) ::
          {:ok, node_map()} | {:error, :invalid_name | :parent_not_found | :parent_archived}
  def create_folder(server, attrs) when is_map(attrs) do
    GenServer.call(server, {:create_folder, attrs})
  end

  @doc """
  Creates a file inside an existing live folder.

  `attrs` accepts `:name` (required, non-empty string), `:parent_id` (required) and `:content`
  (optional string, defaults to `""`). The name is validated before the parent.

  Returns `{:ok, file}`, `{:error, :invalid_name}`, `{:error, :parent_not_found}` or
  `{:error, :parent_archived}`.
  """
  @spec create_file(GenServer.server(), map()) ::
          {:ok, node_map()} | {:error, :invalid_name | :parent_not_found | :parent_archived}
  def create_file(server, attrs) when is_map(attrs) do
    GenServer.call(server, {:create_file, attrs})
  end

  @doc """
  Fetches a single node by id.

  Archived nodes are hidden unless `opts` contains `include_archived: true`.

  Returns `{:ok, node}` or `{:error, :not_found}`.
  """
  @spec fetch_node(GenServer.server(), id(), keyword()) ::
          {:ok, node_map()} | {:error, :not_found}
  def fetch_node(server, id, opts \\ []) when is_list(opts) do
    GenServer.call(server, {:fetch_node, id, opts})
  end

  @doc """
  Lists the direct children of a folder, sorted by id ascending.

  Archived children are excluded unless `opts` contains `include_archived: true`; the folder
  itself is subject to the same visibility rule. Returns `{:error, :not_found}` when the id is
  unknown or refers to a file.

  Returns `{:ok, children}` or `{:error, :not_found}`.
  """
  @spec list_children(GenServer.server(), id(), keyword()) ::
          {:ok, [node_map()]} | {:error, :not_found}
  def list_children(server, folder_id, opts \\ []) when is_list(opts) do
    GenServer.call(server, {:list_children, folder_id, opts})
  end

  @doc """
  Renames a live node. Archived nodes cannot be renamed.

  The new name is validated before the node lookup.

  Returns `{:ok, node}`, `{:error, :invalid_name}` or `{:error, :not_found}`.
  """
  @spec rename_node(GenServer.server(), id(), String.t()) ::
          {:ok, node_map()} | {:error, :invalid_name | :not_found}
  def rename_node(server, id, new_name) do
    GenServer.call(server, {:rename_node, id, new_name})
  end

  @doc """
  Archives a live node, cascading down its whole subtree.

  The target gets `archive_origin: :direct`; every live descendant gets `archive_origin:
  :cascade` and the same `archived_at` timestamp. Already archived descendants are left
  untouched and are not reported.

  Returns `{:ok, %{node: node, cascaded: ids}}` (ids sorted ascending),
  `{:error, :already_archived}` or `{:error, :not_found}`.
  """
  @spec archive_node(GenServer.server(), id()) ::
          {:ok, %{node: node_map(), cascaded: [id()]}}
          | {:error, :already_archived | :not_found}
  def archive_node(server, id) do
    GenServer.call(server, {:archive_node, id})
  end

  @doc """
  Restores a directly archived node together with the descendants that same cascade took down.

  Children whose origin is `:cascade` are restored and walked through; children archived
  directly stay archived and their subtrees are skipped.

  Returns `{:ok, %{node: node, restored: ids}}` (ids sorted ascending), `{:error, :not_found}`,
  `{:error, :not_archived}`, `{:error, :cascade_archived}` or `{:error, :parent_archived}`.
  """
  @spec unarchive_node(GenServer.server(), id()) ::
          {:ok, %{node: node_map(), restored: [id()]}}
          | {:error, :not_found | :not_archived | :cascade_archived | :parent_archived}
  def unarchive_node(server, id) do
    GenServer.call(server, {:unarchive_node, id})
  end

  @doc """
  Lists every archived node (both `:direct` and `:cascade` origins), sorted by id ascending.

  Returns `{:ok, nodes}`.
  """
  @spec list_archived(GenServer.server()) :: {:ok, [node_map()]}
  def list_archived(server) do
    GenServer.call(server, :list_archived)
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl GenServer
  @spec init(:ok) :: {:ok, state()}
  def init(:ok) do
    {:ok, %{nodes: %{}, next_id: 1}}
  end

  @impl GenServer
  def handle_call({:create_folder, attrs}, _from, state) do
    with {:ok, name} <- validate_name(Map.get(attrs, :name)),
         parent_id = Map.get(attrs, :parent_id),
         :ok <- validate_parent(state, parent_id, :folder) do
      insert(state, %{
        type: :folder,
        name: name,
        parent_id: parent_id,
        content: nil
      })
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:create_file, attrs}, _from, state) do
    with {:ok, name} <- validate_name(Map.get(attrs, :name)),
         parent_id = Map.get(attrs, :parent_id),
         :ok <- validate_parent(state, parent_id, :file) do
      insert(state, %{
        type: :file,
        name: name,
        parent_id: parent_id,
        content: normalize_content(Map.get(attrs, :content))
      })
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  def handle_call({:fetch_node, id, opts}, _from, state) do
    case Map.get(state.nodes, id) do
      nil -> {:reply, {:error, :not_found}, state}
      node -> {:reply, visible_reply(node, opts), state}
    end
  end

  def handle_call({:list_children, folder_id, opts}, _from, state) do
    case Map.get(state.nodes, folder_id) do
      %{type: :folder} = folder ->
        if visible?(folder, opts) do
          {:reply, {:ok, children(state.nodes, folder_id, opts)}, state}
        else
          {:reply, {:error, :not_found}, state}
        end

      _other ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:rename_node, id, new_name}, _from, state) do
    with {:ok, name} <- validate_name(new_name),
         %{archived_at: nil} = node <- Map.get(state.nodes, id) do
      updated = %{node | name: name}
      {:reply, {:ok, updated}, put_node(state, updated)}
    else
      {:error, reason} -> {:reply, {:error, reason}, state}
      _archived_or_missing -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:archive_node, id}, _from, state) do
    case Map.get(state.nodes, id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %{archived_at: archived_at} when not is_nil(archived_at) ->
        {:reply, {:error, :already_archived}, state}

      node ->
        now = DateTime.utc_now() |> DateTime.truncate(:second)
        target = %{node | archived_at: now, archive_origin: :direct}
        nodes = Map.put(state.nodes, id, target)
        {nodes, cascaded} = cascade_archive(nodes, id, now)
        state = %{state | nodes: nodes}
        {:reply, {:ok, %{node: target, cascaded: Enum.sort(cascaded)}}, state}
    end
  end

  def handle_call({:unarchive_node, id}, _from, state) do
    case Map.get(state.nodes, id) do
      nil ->
        {:reply, {:error, :not_found}, state}

      %{archived_at: nil} ->
        {:reply, {:error, :not_archived}, state}

      %{archive_origin: :cascade} ->
        {:reply, {:error, :cascade_archived}, state}

      node ->
        if parent_archived?(state.nodes, node.parent_id) do
          {:reply, {:error, :parent_archived}, state}
        else
          target = %{node | archived_at: nil, archive_origin: nil}
          nodes = Map.put(state.nodes, id, target)
          {nodes, restored} = cascade_restore(nodes, id)
          state = %{state | nodes: nodes}
          {:reply, {:ok, %{node: target, restored: Enum.sort(restored)}}, state}
        end
    end
  end

  def handle_call(:list_archived, _from, state) do
    archived =
      state.nodes
      |> Map.values()
      |> Enum.reject(&is_nil(&1.archived_at))
      |> Enum.sort_by(& &1.id)

    {:reply, {:ok, archived}, state}
  end

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  @spec insert(state(), map()) :: {:reply, {:ok, node_map()}, state()}
  defp insert(state, fields) do
    id = state.next_id

    node = %{
      id: id,
      type: fields.type,
      name: fields.name,
      parent_id: fields.parent_id,
      content: fields.content,
      archived_at: nil,
      archive_origin: nil
    }

    state = %{state | nodes: Map.put(state.nodes, id, node), next_id: id + 1}
    {:reply, {:ok, node}, state}
  end

  @spec put_node(state(), node_map()) :: state()
  defp put_node(state, node), do: %{state | nodes: Map.put(state.nodes, node.id, node)}

  @spec validate_name(term()) :: {:ok, String.t()} | {:error, :invalid_name}
  defp validate_name(name) when is_binary(name) do
    if String.trim(name) == "" do
      {:error, :invalid_name}
    else
      {:ok, name}
    end
  end

  defp validate_name(_name), do: {:error, :invalid_name}

  @spec validate_parent(state(), term(), node_type()) ::
          :ok | {:error, :parent_not_found | :parent_archived}
  defp validate_parent(_state, nil, :folder), do: :ok
  defp validate_parent(_state, nil, :file), do: {:error, :parent_not_found}

  defp validate_parent(state, parent_id, _type) do
    case Map.get(state.nodes, parent_id) do
      %{type: :folder, archived_at: nil} -> :ok
      %{type: :folder} -> {:error, :parent_archived}
      _missing_or_file -> {:error, :parent_not_found}
    end
  end

  @spec normalize_content(term()) :: String.t()
  defp normalize_content(content) when is_binary(content), do: content
  defp normalize_content(_content), do: ""

  @spec visible?(node_map(), keyword()) :: boolean()
  defp visible?(%{archived_at: nil}, _opts), do: true
  defp visible?(_node, opts), do: Keyword.get(opts, :include_archived, false) == true

  @spec visible_reply(node_map(), keyword()) :: {:ok, node_map()} | {:error, :not_found}
  defp visible_reply(node, opts) do
    if visible?(node, opts), do: {:ok, node}, else: {:error, :not_found}
  end

  @spec children(%{optional(id()) => node_map()}, id(), keyword()) :: [node_map()]
  defp children(nodes, parent_id, opts) do
    nodes
    |> Map.values()
    |> Enum.filter(&(&1.parent_id == parent_id and visible?(&1, opts)))
    |> Enum.sort_by(& &1.id)
  end

  @spec child_ids(%{optional(id()) => node_map()}, id()) :: [id()]
  defp child_ids(nodes, parent_id) do
    nodes
    |> Map.values()
    |> Enum.filter(&(&1.parent_id == parent_id))
    |> Enum.map(& &1.id)
    |> Enum.sort()
  end

  @spec parent_archived?(%{optional(id()) => node_map()}, id() | nil) :: boolean()
  defp parent_archived?(_nodes, nil), do: false

  defp parent_archived?(nodes, parent_id) do
    case Map.get(nodes, parent_id) do
      %{archived_at: nil} -> false
      nil -> false
      _archived -> true
    end
  end

  @spec cascade_archive(%{optional(id()) => node_map()}, id(), DateTime.t()) ::
          {%{optional(id()) => node_map()}, [id()]}
  defp cascade_archive(nodes, parent_id, now) do
    nodes
    |> child_ids(parent_id)
    |> Enum.reduce({nodes, []}, fn child_id, {acc_nodes, acc_ids} ->
      case Map.fetch!(acc_nodes, child_id) do
        %{archived_at: nil} = child ->
          archived = %{child | archived_at: now, archive_origin: :cascade}
          acc_nodes = Map.put(acc_nodes, child_id, archived)
          {acc_nodes, deeper} = cascade_archive(acc_nodes, child_id, now)
          {acc_nodes, [child_id | deeper] ++ acc_ids}

        _already_archived ->
          {acc_nodes, acc_ids}
      end
    end)
  end

  @spec cascade_restore(%{optional(id()) => node_map()}, id()) ::
          {%{optional(id()) => node_map()}, [id()]}
  defp cascade_restore(nodes, parent_id) do
    nodes
    |> child_ids(parent_id)
    |> Enum.reduce({nodes, []}, fn child_id, {acc_nodes, acc_ids} ->
      case Map.fetch!(acc_nodes, child_id) do
        %{archive_origin: :cascade} = child ->
          restored = %{child | archived_at: nil, archive_origin: nil}
          acc_nodes = Map.put(acc_nodes, child_id, restored)
          {acc_nodes, deeper} = cascade_restore(acc_nodes, child_id)
          {acc_nodes, [child_id | deeper] ++ acc_ids}

        _live_or_direct ->
          {acc_nodes, acc_ids}
      end
    end)
  end
end