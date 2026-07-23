# Adapt existing code to a new specification

Below is a complete, working, tested Elixir solution to a related task. Do not
start from scratch: treat it as the codebase you have been asked to change.
Modify it to satisfy the new specification that follows — keep whatever carries
over, and change, add, or remove whatever the new specification requires.

Where the existing code and the new specification disagree (module name, public
API, behavior, constraints, output format), the new specification wins. Give me
the complete final result.

## Existing code (your starting point)

```elixir
defmodule ObjectStore do
  @moduledoc """
  A content-addressable object store implemented as a GenServer,
  similar in spirit to Git's object model.

  All objects (blobs, trees, commits) are stored in a single flat
  map keyed by their SHA-1 hex digest. Storing identical content
  is idempotent — it always returns the same hash.
  """

  use GenServer

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Starts the ObjectStore process.

  ## Options
    * `:name` — optional process registration name.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    {name, _rest} = Keyword.pop(opts, :name)
    server_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, %{}, server_opts)
  end

  @doc """
  Stores an arbitrary binary and returns its SHA-1 hex digest.

  Idempotent — storing the same content twice returns the same hash
  without duplicating data.
  """
  @spec store(GenServer.server(), binary()) :: {:ok, String.t()}
  def store(server, content) when is_binary(content) do
    GenServer.call(server, {:store, content})
  end

  @doc """
  Retrieves previously-stored content by its SHA-1 hex digest.

  Returns `{:ok, content}` or `{:error, :not_found}`.
  """
  @spec retrieve(GenServer.server(), String.t()) :: {:ok, binary()} | {:error, :not_found}
  def retrieve(server, hash) when is_binary(hash) do
    GenServer.call(server, {:retrieve, hash})
  end

  @doc """
  Creates a tree object from a list of entry maps.

  Each entry must contain:
    * `:name`  — filename (string)
    * `:hash`  — SHA-1 hex of an already-stored object
    * `:type`  — `:blob` or `:tree`

  Entries are sorted alphabetically by `:name` before serialization,
  so the resulting hash is independent of input order.
  """
  @spec tree(GenServer.server(), [map()]) :: {:ok, String.t()}
  def tree(server, entries) when is_list(entries) do
    GenServer.call(server, {:tree, entries})
  end

  @doc """
  Creates a commit object.

  * `tree_hash`   — SHA-1 of the tree object for this commit
  * `parent_hash` — SHA-1 of the parent commit, or `nil` for the initial commit
  * `message`     — commit message (string)
  * `author`      — author name (string)
  """
  @spec commit(GenServer.server(), String.t(), String.t() | nil, String.t(), String.t()) ::
          {:ok, String.t()}
  def commit(server, tree_hash, parent_hash, message, author) do
    GenServer.call(server, {:commit, tree_hash, parent_hash, message, author})
  end

  @doc """
  Walks the parent chain starting from `commit_hash` and returns a list
  of commit maps ordered from newest to oldest.

  Each map contains `:hash`, `:message`, `:author`, `:tree`, and `:parent`.

  Returns `{:error, :not_found}` if the starting hash does not exist.
  """
  @spec log(GenServer.server(), String.t()) ::
          {:ok, [map()]} | {:error, :not_found}
  def log(server, commit_hash) when is_binary(commit_hash) do
    GenServer.call(server, {:log, commit_hash})
  end

  # ---------------------------------------------------------------------------
  # GenServer callbacks
  # ---------------------------------------------------------------------------

  @impl true
  def init(state) do
    {:ok, state}
  end

  @impl true
  def handle_call({:store, content}, _from, state) do
    {hash, state} = do_store(state, content)
    {:reply, {:ok, hash}, state}
  end

  def handle_call({:retrieve, hash}, _from, state) do
    case Map.fetch(state, hash) do
      {:ok, content} -> {:reply, {:ok, content}, state}
      :error -> {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:tree, entries}, _from, state) do
    serialized =
      entries
      |> Enum.sort_by(& &1.name)
      |> Enum.map_join("\n", fn entry ->
        type_str = Atom.to_string(entry.type)
        "#{type_str} #{entry.hash} #{entry.name}"
      end)

    {hash, state} = do_store(state, serialized)
    {:reply, {:ok, hash}, state}
  end

  def handle_call({:commit, tree_hash, parent_hash, message, author}, _from, state) do
    parent_str = parent_hash || "nil"

    serialized =
      "tree #{tree_hash}\nparent #{parent_str}\nauthor #{author}\nmessage #{message}"

    {hash, state} = do_store(state, serialized)
    {:reply, {:ok, hash}, state}
  end

  def handle_call({:log, commit_hash}, _from, state) do
    case walk_log(state, commit_hash, []) do
      {:ok, entries} -> {:reply, {:ok, entries}, state}
      {:error, _} = err -> {:reply, err, state}
    end
  end

  # ---------------------------------------------------------------------------
  # Internal helpers
  # ---------------------------------------------------------------------------

  defp do_store(state, content) do
    hash = sha1(content)
    {hash, Map.put_new(state, hash, content)}
  end

  defp sha1(content) do
    :crypto.hash(:sha, content)
    |> Base.encode16(case: :lower)
  end

  defp walk_log(_state, nil, acc), do: {:ok, Enum.reverse(acc)}

  defp walk_log(state, hash, acc) do
    case Map.fetch(state, hash) do
      :error when acc == [] ->
        {:error, :not_found}

      :error ->
        # Dangling parent reference — stop gracefully.
        {:ok, Enum.reverse(acc)}

      {:ok, content} ->
        parsed = parse_commit(content)

        entry = %{
          hash: hash,
          tree: parsed.tree,
          parent: parsed.parent,
          author: parsed.author,
          message: parsed.message
        }

        walk_log(state, parsed.parent, [entry | acc])
    end
  end

  defp parse_commit(content) do
    lines = String.split(content, "\n", parts: 4)

    raw_parent = strip_prefix(Enum.at(lines, 1), "parent ")
    parent = if raw_parent == "nil", do: nil, else: raw_parent

    %{
      tree: strip_prefix(Enum.at(lines, 0), "tree "),
      parent: parent,
      author: strip_prefix(Enum.at(lines, 2), "author "),
      message: strip_prefix(Enum.at(lines, 3), "message ")
    }
  end

  defp strip_prefix(str, prefix) do
    String.replace_prefix(str, prefix, "")
  end
end
```

## New specification

I need you to write me an Elixir GenServer module called `ObjectStore` — a content-addressable object store, but one that actually **persists objects to disk** as compressed "loose object" files, the way Git does under `.git/objects`, and that **verifies integrity on read**. The key thing for me is that the store keeps no in-memory copy of object contents — every read and every write goes to the filesystem. That way a second process pointed at the same directory sees the same objects, and objects survive process restarts.

Here's the public API I'm after:

`ObjectStore.start_link(opts)` starts the process and returns `{:ok, pid}`. It should accept an optional `:name` option for process registration — when it's given, register the process under that atom, so `Process.whereis(name)` returns the pid and the name can be handed to every other function as `server`. It also takes a **required** `:dir` option naming the directory the objects live in. Please fetch `:dir` with `Keyword.fetch!/2` so that calling `start_link/1` without it raises `KeyError`. If the directory doesn't exist yet, create it on startup, including any missing parent directories.

`ObjectStore.store(server, content)` takes an arbitrary binary/string, computes its SHA-1 hash (lowercase hex), writes the object to disk, and returns `{:ok, hash}`. Storing the same content twice has to be idempotent — same hash back, and no rewriting the file if it's already there (I care that the existing file's mtime is left untouched). Empty content and content with arbitrary bytes, null bytes included, must round-trip.

`ObjectStore.retrieve(server, hash)` reads the object file for `hash`, decompresses it, and returns `{:ok, content}` where `content` is the exact binary that went in. If there's no file for that hash, return `{:error, :not_found}`. If the file exists but won't decompress, or the SHA-1 of the decompressed bytes doesn't equal the requested hash, return `{:error, :corrupt}` — and please catch the decompression failure rather than letting it crash the process.

`ObjectStore.has_object?(server, hash)` returns `true` if an object file exists for `hash`, `false` otherwise.

`ObjectStore.list_objects(server)` returns a sorted list of the SHA-1 hex hashes of every object currently on disk, or `[]` when the store is empty. Since it scans the directory on each call, it needs to pick up objects written by another process pointed at the same directory.

The on-disk layout is a fixed contract, so don't improvise here: the file path for an object with hash `H` is `<dir>/<first two characters of H>/<remaining 38 characters of H>` — the object goes in a two-character fan-out subdirectory named by the first two hex characters, in a file named by the remaining 38. The file contents are the **zlib-compressed** raw object bytes; compress with `:zlib.compress/1` and decompress with `:zlib.uncompress/1`.

Two implementation points I want followed: use `:crypto.hash(:sha, content)` and `Base.encode16(hash, case: :lower)` for the SHA-1 hashing, and keep all object contents on disk — no in-memory content map in the process state.

Give me the complete module in a single file, using only the OTP standard library, no external dependencies.
