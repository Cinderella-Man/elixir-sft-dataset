# Implement the missing function

Below is the complete specification of a task, followed by a working,
fully tested module that solves it — except that `branch_head` has been
removed: every clause body is blanked to `# TODO`. Implement exactly that
function so the whole module passes the task's full test suite again.
Change nothing else — every other function, attribute, and clause must
stay exactly as shown.

## The task

# Specification: `ObjectStore` — Content-Addressable Object Store with Mutable Branch References and Reachability GC

## Overview

This document specifies an Elixir GenServer module named `ObjectStore` that implements a content-addressable object store with a layer of **mutable named branch references** on top of the immutable objects, plus **reachability-based garbage collection** — like Git's refs (branches) and `git gc`. Objects are immutable and content-addressed; branches are mutable pointers to commit hashes, updated with an atomic compare-and-swap, and unreferenced objects can be swept away.

The deliverable is the complete module in a single file. Only the OTP standard library may be used; no external dependencies.

## API

The following functions constitute the public API.

### `ObjectStore.start_link(opts)`

Starts the process. It accepts an optional `:name` option for process registration; it must also work when called with an empty list, e.g. `ObjectStore.start_link([])`. When `:name` is given, all API functions must work when passed that name in place of a pid. Internal state holds an in-memory map of SHA-1 hex digest → stored binary content, plus a separate mapping of branch name → commit hash.

### `ObjectStore.store(server, content)`

Computes the SHA-1 (lowercase hex) of `content`, persists the raw bytes keyed by that hash, and returns `{:ok, hash}`. `content` is an arbitrary binary and may contain null bytes; it is stored and returned byte-for-byte. The operation is idempotent — the same content yields the same hash and is stored only once, so storing it twice leaves exactly one object.

### `ObjectStore.retrieve(server, hash)`

Returns `{:ok, content}` with the exact bytes that were stored, or `{:error, :not_found}`.

### `ObjectStore.commit(server, tree_hash, parent_hash, message, author)`

Creates a commit object. `tree_hash` is a SHA-1 string of any stored object. `parent_hash` is either a SHA-1 string of the parent commit or `nil` for a root commit. `message` and `author` are strings. The implementation builds a deterministic text representation (same arguments always give the same hash; changing the message or the author alone must change the hash), stores it as a normal object — retrievable via `retrieve/2`, with a hash equal to the SHA-1 of its own serialized bytes — and returns `{:ok, commit_hash}`.

### `ObjectStore.create_branch(server, name, commit_hash)`

Creates a branch named `name` (a string) pointing at `commit_hash`. Returns `{:ok, name}`. If a branch with that name already exists, it returns `{:error, :exists}`. If `commit_hash` is not an existing stored object, it returns `{:error, :not_found}`. Any stored object is an acceptable target — a branch may point at a plain blob, not just a commit.

### `ObjectStore.branch_head(server, name)`

Returns `{:ok, commit_hash}` for the commit a branch points at, or `{:error, :no_branch}` if no such branch exists.

### `ObjectStore.update_branch(server, name, expected_hash, new_hash)`

Performs an atomic compare-and-swap: it moves branch `name` to `new_hash` **only if** the branch currently points at `expected_hash`. On success it returns `{:ok, new_hash}` (including the no-op case where `new_hash` equals the current head). If the branch does not exist, it returns `{:error, :no_branch}`. If `new_hash` is not an existing stored object, it returns `{:error, :not_found}`. If the branch exists but does not currently point at `expected_hash`, it returns `{:error, :conflict}` and leaves the branch unchanged.

### `ObjectStore.delete_branch(server, name)`

Removes a branch and returns `:ok`, or `{:error, :no_branch}` if it does not exist.

### `ObjectStore.list_branches(server)`

Returns a map of branch name → commit hash for all branches — `%{}` for a fresh store, and reflecting creations, compare-and-swap moves, and deletions.

### `ObjectStore.gc(server)`

Garbage-collects unreferenced objects and returns `{:ok, removed_count}`, the number of objects deleted (`{:ok, 0}` when nothing is unreachable, so repeated calls converge). An object is **reachable** if any of the following holds: (a) it is the object a branch points at directly (commit or blob); (b) it is an ancestor commit found by following `parent` links transitively — through arbitrarily many hops — from any branch head; or (c) it is the tree object referenced (via `tree_hash`) by any reachable commit, including trees of ancestor commits. Every stored object that is not reachable is deleted.

## Edge cases

- `content` passed to `store/2` may contain null bytes; the bytes round-trip unchanged.
- Storing identical content twice results in exactly one stored object.
- `retrieve/2` on an unknown hash yields `{:error, :not_found}`.
- `parent_hash` of `nil` in `commit/5` denotes a root commit.
- Two commits differing only in `message`, or only in `author`, must hash differently.
- `create_branch/3` on an existing name yields `{:error, :exists}`; on a hash that is not an existing stored object it yields `{:error, :not_found}`.
- A branch may point at a plain blob rather than a commit.
- `branch_head/2` and `delete_branch/2` on a missing branch yield `{:error, :no_branch}`.
- `update_branch/4` where `new_hash` equals the current head still succeeds with `{:ok, new_hash}`.
- `update_branch/4` on a missing branch yields `{:error, :no_branch}`; with a `new_hash` that is not an existing stored object it yields `{:error, :not_found}`; on a head mismatch it yields `{:error, :conflict}` with the branch left unchanged.
- `list_branches/1` returns `%{}` for a fresh store.
- With no branches at all, `gc/1` sweeps everything.
- A loose blob that is not referenced as some reachable commit's tree is unreachable and will be removed.
- Repeated `gc/1` calls converge, returning `{:ok, 0}` once nothing is unreachable.

## Implementation requirements

- SHA-1 hashing uses `:crypto.hash(:sha, content)` and `Base.encode16(hash, case: :lower)`.
- Commit serialization must be deterministic and include the tree, parent (using the literal `nil` when there is no parent), author, and message so that ancestry and tree references can be recovered when computing reachability.
- All stored objects (blobs and commits) live in the same flat hash map; branches live in a separate map.

## The module with `branch_head` missing

```elixir
defmodule ObjectStore do
  @moduledoc """
  A content-addressable object store with mutable named branch references and
  reachability-based garbage collection, modeled loosely on Git.

  Objects (blobs and commits) are immutable and addressed by the SHA-1 hex
  digest of their raw bytes. They all live in a single flat map from hash to
  binary content.

  Branches are mutable named pointers to commit hashes. They live in a separate
  map and are updated with an atomic compare-and-swap.

  Garbage collection walks the reachability graph starting from every branch
  head — following `parent` links to ancestor commits and `tree_hash`
  references to tree objects — and deletes every stored object that is not
  reachable.
  """

  use GenServer

  @typedoc "A SHA-1 hex digest (lowercase)."
  @type hash :: String.t()

  @typedoc "Internal server state."
  @type state :: %{
          objects: %{optional(hash) => binary()},
          branches: %{optional(String.t()) => hash}
        }

  # Public API

  @doc """
  Starts the object store process.

  Accepts an optional `:name` for process registration; all other options are
  passed through to `GenServer.start_link/3`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name)

    case name do
      nil -> GenServer.start_link(__MODULE__, :ok, opts)
      name -> GenServer.start_link(__MODULE__, :ok, [{:name, name} | opts])
    end
  end

  @doc """
  Stores raw `content`, returning `{:ok, hash}` where `hash` is its SHA-1 hex
  digest. Idempotent: identical content always yields the same hash and is not
  duplicated.
  """
  @spec store(GenServer.server(), binary()) :: {:ok, hash}
  def store(server, content) when is_binary(content) do
    GenServer.call(server, {:store, content})
  end

  @doc """
  Retrieves the content stored under `hash`, or `{:error, :not_found}`.
  """
  @spec retrieve(GenServer.server(), hash) :: {:ok, binary()} | {:error, :not_found}
  def retrieve(server, hash) when is_binary(hash) do
    GenServer.call(server, {:retrieve, hash})
  end

  @doc """
  Creates and stores a commit object referencing `tree_hash` with parent
  `parent_hash` (or `nil` for a root commit), along with `message` and
  `author`. Returns `{:ok, commit_hash}`. Deterministic: identical arguments
  always produce the same commit hash.
  """
  @spec commit(GenServer.server(), hash, hash | nil, String.t(), String.t()) :: {:ok, hash}
  def commit(server, tree_hash, parent_hash, message, author)
      when is_binary(tree_hash) and (is_binary(parent_hash) or is_nil(parent_hash)) and
             is_binary(message) and is_binary(author) do
    GenServer.call(server, {:commit, tree_hash, parent_hash, message, author})
  end

  @doc """
  Creates a branch `name` pointing at `commit_hash`.

  Returns `{:ok, name}` on success, `{:error, :exists}` if the branch already
  exists, or `{:error, :not_found}` if `commit_hash` is not a stored object.
  """
  @spec create_branch(GenServer.server(), String.t(), hash) ::
          {:ok, String.t()} | {:error, :exists | :not_found}
  def create_branch(server, name, commit_hash) when is_binary(name) and is_binary(commit_hash) do
    GenServer.call(server, {:create_branch, name, commit_hash})
  end

  def branch_head(server, name) when is_binary(name) do
    # TODO
  end

  @doc """
  Atomically moves branch `name` from `expected_hash` to `new_hash`.

  Returns `{:ok, new_hash}` on success. Returns `{:error, :no_branch}` if the
  branch does not exist, `{:error, :not_found}` if `new_hash` is not a stored
  object, or `{:error, :conflict}` (leaving the branch unchanged) if the branch
  does not currently point at `expected_hash`.
  """
  @spec update_branch(GenServer.server(), String.t(), hash, hash) ::
          {:ok, hash} | {:error, :no_branch | :not_found | :conflict}
  def update_branch(server, name, expected_hash, new_hash)
      when is_binary(name) and is_binary(expected_hash) and is_binary(new_hash) do
    GenServer.call(server, {:update_branch, name, expected_hash, new_hash})
  end

  @doc """
  Deletes branch `name`. Returns `:ok`, or `{:error, :no_branch}` if it does
  not exist.
  """
  @spec delete_branch(GenServer.server(), String.t()) :: :ok | {:error, :no_branch}
  def delete_branch(server, name) when is_binary(name) do
    GenServer.call(server, {:delete_branch, name})
  end

  @doc """
  Returns a map of branch name to commit hash for all branches.
  """
  @spec list_branches(GenServer.server()) :: %{optional(String.t()) => hash}
  def list_branches(server) do
    GenServer.call(server, :list_branches)
  end

  @doc """
  Garbage-collects unreferenced objects, returning `{:ok, removed_count}`.

  An object is reachable if it is a branch head, an ancestor commit reachable
  by following `parent` links from a branch head, or the tree referenced by a
  reachable commit. All other stored objects are deleted.
  """
  @spec gc(GenServer.server()) :: {:ok, non_neg_integer()}
  def gc(server) do
    GenServer.call(server, :gc)
  end

  # GenServer callbacks

  @impl true
  @spec init(:ok) :: {:ok, state}
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

  @spec hash_content(binary()) :: hash
  defp hash_content(content) do
    :sha
    |> :crypto.hash(content)
    |> Base.encode16(case: :lower)
  end

  @spec serialize_commit(hash, hash | nil, String.t(), String.t()) :: binary()
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

  @spec parse_commit(binary()) :: {:ok, %{tree: hash, parent: hash | nil}} | :error
  defp parse_commit(content) do
    case String.split(content, "\n") do
      ["commit", "tree " <> tree, "parent " <> parent | _rest] ->
        parent = if parent == "nil", do: nil, else: parent
        {:ok, %{tree: tree, parent: parent}}

      _other ->
        :error
    end
  end

  @spec reachable_set(state) :: MapSet.t(hash)
  defp reachable_set(state) do
    heads = Map.values(state.branches)
    walk(heads, state.objects, MapSet.new())
  end

  @spec walk([hash], %{optional(hash) => binary()}, MapSet.t(hash)) :: MapSet.t(hash)
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

  @spec commit_refs(binary()) :: [hash]
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

Give me only the complete implementation of `branch_head` (including any
`@doc`/`@spec`/`@impl` lines that belong directly above it) — the
function alone, not the whole module.
