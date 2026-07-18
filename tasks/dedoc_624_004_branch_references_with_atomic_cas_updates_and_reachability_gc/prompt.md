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
defmodule ObjectStore do
  use GenServer

  # Public API

  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)

    case name do
      nil -> GenServer.start_link(__MODULE__, :ok, opts)
      name -> GenServer.start_link(__MODULE__, :ok, [{:name, name} | opts])
    end
  end

  def store(server, content) when is_binary(content) do
    GenServer.call(server, {:store, content})
  end

  def retrieve(server, hash) when is_binary(hash) do
    GenServer.call(server, {:retrieve, hash})
  end

  def commit(server, tree_hash, parent_hash, message, author)
      when is_binary(tree_hash) and (is_binary(parent_hash) or is_nil(parent_hash)) and
             is_binary(message) and is_binary(author) do
    GenServer.call(server, {:commit, tree_hash, parent_hash, message, author})
  end

  def create_branch(server, name, commit_hash) when is_binary(name) and is_binary(commit_hash) do
    GenServer.call(server, {:create_branch, name, commit_hash})
  end

  def branch_head(server, name) when is_binary(name) do
    GenServer.call(server, {:branch_head, name})
  end

  def update_branch(server, name, expected_hash, new_hash)
      when is_binary(name) and is_binary(expected_hash) and is_binary(new_hash) do
    GenServer.call(server, {:update_branch, name, expected_hash, new_hash})
  end

  def delete_branch(server, name) when is_binary(name) do
    GenServer.call(server, {:delete_branch, name})
  end

  def list_branches(server) do
    GenServer.call(server, :list_branches)
  end

  def gc(server) do
    GenServer.call(server, :gc)
  end

  # GenServer callbacks

  @impl true
  def init(:ok) do
    {:ok, %{objects: %{}, branches: %{}}}
  end

  @impl true
  def handle_call({:store, content}, _from, state) do
    hash = hash_content(content)
    objects = Map.put_new(state.objects, hash, content)
    {:reply, {:ok, hash}, %{state | objects: objects}}
  end

  def handle_call({:retrieve, hash}, _from, state) do
    case Map.fetch(state.objects, hash) do
      {:ok, content} -> {:reply, {:ok, content}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:commit, tree_hash, parent_hash, message, author}, _from, state) do
    content = serialize_commit(tree_hash, parent_hash, message, author)
    hash = hash_content(content)
    objects = Map.put_new(state.objects, hash, content)
    {:reply, {:ok, hash}, %{state | objects: objects}}
  end

  def handle_call({:create_branch, name, commit_hash}, _from, state) do
    cond do
      Map.has_key?(state.branches, name) ->
        {:reply, {:error, :exists}, state}

      not Map.has_key?(state.objects, commit_hash) ->
        {:reply, {:error, :not_found}, state}

      true ->
        branches = Map.put(state.branches, name, commit_hash)
        {:reply, {:ok, name}, %{state | branches: branches}}
    end
  end

  def handle_call({:branch_head, name}, _from, state) do
    case Map.fetch(state.branches, name) do
      {:ok, commit_hash} -> {:reply, {:ok, commit_hash}, state}
      :error -> {:reply, {:error, :no_branch}, state}
    end
  end

  def handle_call({:update_branch, name, expected_hash, new_hash}, _from, state) do
    cond do
      not Map.has_key?(state.branches, name) ->
        {:reply, {:error, :no_branch}, state}

      not Map.has_key?(state.objects, new_hash) ->
        {:reply, {:error, :not_found}, state}

      Map.fetch!(state.branches, name) != expected_hash ->
        {:reply, {:error, :conflict}, state}

      true ->
        branches = Map.put(state.branches, name, new_hash)
        {:reply, {:ok, new_hash}, %{state | branches: branches}}
    end
  end

  def handle_call({:delete_branch, name}, _from, state) do
    case Map.has_key?(state.branches, name) do
      true -> {:reply, :ok, %{state | branches: Map.delete(state.branches, name)}}
      false -> {:reply, {:error, :no_branch}, state}
    end
  end

  def handle_call(:list_branches, _from, state) do
    {:reply, state.branches, state}
  end

  def handle_call(:gc, _from, state) do
    reachable = reachable_set(state)

    {kept, removed_count} =
      Enum.reduce(state.objects, {%{}, 0}, fn {hash, content}, {acc, count} ->
        case MapSet.member?(reachable, hash) do
          true -> {Map.put(acc, hash, content), count}
          false -> {acc, count + 1}
        end
      end)

    {:reply, {:ok, removed_count}, %{state | objects: kept}}
  end

  # Internal helpers

  defp hash_content(content) do
    :sha
    |> :crypto.hash(content)
    |> Base.encode16(case: :lower)
  end

  defp serialize_commit(tree_hash, parent_hash, message, author) do
    parent_line = if is_nil(parent_hash), do: "parent nil", else: "parent #{parent_hash}"

    Enum.join(
      [
        "commit",
        "tree #{tree_hash}",
        parent_line,
        "author #{author}",
        "",
        message
      ],
      "\n"
    )
  end

  defp parse_commit(content) do
    case String.split(content, "\n") do
      ["commit", "tree " <> tree, "parent " <> parent | _rest] ->
        parent = if parent == "nil", do: nil, else: parent
        {:ok, %{tree: tree, parent: parent}}

      _other ->
        :error
    end
  end

  defp reachable_set(state) do
    heads = Map.values(state.branches)
    walk(heads, state.objects, MapSet.new())
  end

  defp walk([], _objects, acc), do: acc

  defp walk([hash | rest], objects, acc) do
    cond do
      MapSet.member?(acc, hash) ->
        walk(rest, objects, acc)

      not Map.has_key?(objects, hash) ->
        walk(rest, objects, acc)

      true ->
        acc = MapSet.put(acc, hash)
        extra = commit_refs(Map.fetch!(objects, hash))
        walk(extra ++ rest, objects, acc)
    end
  end

  defp commit_refs(content) do
    case parse_commit(content) do
      {:ok, %{tree: tree, parent: parent}} ->
        refs = [tree]
        if is_nil(parent), do: refs, else: [parent | refs]

      :error ->
        []
    end
  end
end
```
