defmodule InvertedIndex do
  @moduledoc """
  A crash-recoverable, disk-persistent full-text search engine.

  `InvertedIndex` is a `GenServer` that maintains an in-memory inverted index
  while durably recording every mutation on disk before acknowledging it. Two
  files are kept inside the configured `:dir`:

    * a write-ahead log (`wal.log`) — every `index`/`remove` mutation is
      appended and flushed (`:file.sync/1`) before the call returns, so a hard
      kill never loses an acknowledged write;
    * a snapshot (`snapshot.bin`) — a compacted image of the whole index that
      recovery loads first, after which only the WAL entries written since the
      snapshot are replayed.

  On start the server rebuilds its state from `:dir`: it loads the snapshot (if
  any) and replays the WAL in order. Servers using different directories are
  completely independent. All term storage and lookup are case-insensitive.
  """

  use GenServer

  @default_stop_words MapSet.new([
                        "the",
                        "a",
                        "an",
                        "is",
                        "are",
                        "was",
                        "were",
                        "in",
                        "on",
                        "at",
                        "to",
                        "of",
                        "and",
                        "or",
                        "it",
                        "this",
                        "that",
                        "for",
                        "with",
                        "as",
                        "by",
                        "not",
                        "be",
                        "has",
                        "had",
                        "have",
                        "do",
                        "does",
                        "did",
                        "but",
                        "if",
                        "from"
                      ])

  @type score_entry :: %{id: String.t(), score: float()}

  # ── Public API ────────────────────────────────────────────────────────────

  @doc """
  Starts the index server.

  Options:

    * `:dir` (required) — directory used for the WAL and snapshot files; it is
      created if it does not exist. State is recovered from this directory.
    * `:name` — optional process registration name.
    * `:stop_words` — a `MapSet` of words excluded during tokenization; a
      built-in default set is used when omitted.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    {name, opts} = Keyword.pop(opts, :name)
    gen_opts = if name, do: [name: name], else: []
    GenServer.start_link(__MODULE__, opts, gen_opts)
  end

  @doc """
  Indexes `id` with `fields`, a map of field names to text strings.

  The mutation is durably appended to the WAL (and flushed) before returning.
  Re-indexing an existing `id` cleanly replaces the previous version.
  """
  @spec index(GenServer.server(), String.t(), map()) :: :ok
  def index(server, id, fields) do
    GenServer.call(server, {:index, id, fields})
  end

  @doc """
  Removes the document `id` entirely.

  The mutation is durably appended to the WAL before returning. Removing an
  unknown id is a no-op and never raises.
  """
  @spec remove(GenServer.server(), String.t()) :: :ok
  def remove(server, id) do
    GenServer.call(server, {:remove, id})
  end

  @doc """
  Searches for documents matching `query`, ranked by summed TF-IDF descending.

  A document matches when it contains at least one query term. `opts[:limit]`
  caps the number of returned results.
  """
  @spec search(GenServer.server(), String.t(), keyword()) :: [score_entry()]
  def search(server, query, opts \\ []) do
    GenServer.call(server, {:search, query, opts})
  end

  @doc """
  Writes a fresh snapshot of the whole index and truncates the WAL.

  Compaction never changes query results.
  """
  @spec snapshot(GenServer.server()) :: :ok
  def snapshot(server) do
    GenServer.call(server, :snapshot)
  end

  @doc """
  Returns up to `limit` vocabulary terms starting with the lowercased `prefix`,
  sorted by document frequency descending.
  """
  @spec suggest(GenServer.server(), String.t(), non_neg_integer()) :: [String.t()]
  def suggest(server, prefix, limit \\ 10) do
    GenServer.call(server, {:suggest, prefix, limit})
  end

  @doc """
  Returns `%{document_count: integer, term_count: integer}` for the index.
  """
  @spec stats(GenServer.server()) ::
          %{document_count: non_neg_integer(), term_count: non_neg_integer()}
  def stats(server) do
    GenServer.call(server, :stats)
  end

  # ── GenServer callbacks ───────────────────────────────────────────────────

  @impl true
  def init(opts) do
    dir = Keyword.fetch!(opts, :dir)
    File.mkdir_p!(dir)
    stop_words = Keyword.get(opts, :stop_words, @default_stop_words)
    snapshot_path = Path.join(dir, "snapshot.bin")
    wal_path = Path.join(dir, "wal.log")

    doc_index = load_snapshot(snapshot_path)
    postings = build_postings(doc_index)

    base = %{
      dir: dir,
      stop_words: stop_words,
      snapshot_path: snapshot_path,
      wal_path: wal_path,
      doc_index: doc_index,
      postings: postings,
      wal: nil
    }

    base = replay_wal(read_wal(wal_path), base)
    {:ok, wal} = :file.open(wal_path, [:append, :binary, :raw])
    {:ok, %{base | wal: wal}}
  end

  @impl true
  def handle_call({:index, id, fields}, _from, state) do
    wal_append(state.wal, {:index, id, fields})
    {:reply, :ok, apply_index(state, id, fields)}
  end

  def handle_call({:remove, id}, _from, state) do
    wal_append(state.wal, {:remove, id})
    {:reply, :ok, apply_remove(state, id)}
  end

  def handle_call({:search, query, opts}, _from, state) do
    {:reply, do_search(state, query, opts), state}
  end

  def handle_call(:snapshot, _from, state) do
    {:reply, :ok, do_snapshot(state)}
  end

  def handle_call({:suggest, prefix, limit}, _from, state) do
    {:reply, do_suggest(state, prefix, limit), state}
  end

  def handle_call(:stats, _from, state) do
    stats = %{
      document_count: map_size(state.doc_index),
      term_count: map_size(state.postings)
    }

    {:reply, stats, state}
  end

  @impl true
  def terminate(_reason, state) do
    if state.wal, do: :file.close(state.wal)
    :ok
  end

  # ── Persistence helpers ───────────────────────────────────────────────────

  @spec load_snapshot(String.t()) :: map()
  defp load_snapshot(path) do
    case File.read(path) do
      {:ok, bin} when byte_size(bin) > 0 -> :erlang.binary_to_term(bin)
      _ -> %{}
    end
  end

  @spec read_wal(String.t()) :: binary()
  defp read_wal(path) do
    case File.read(path) do
      {:ok, bin} -> bin
      _ -> ""
    end
  end

  @spec replay_wal(binary(), map()) :: map()
  defp replay_wal(<<len::unsigned-big-integer-size(64), rest::binary>>, state)
       when byte_size(rest) >= len do
    <<payload::binary-size(len), tail::binary>> = rest
    state = apply_entry(state, :erlang.binary_to_term(payload))
    replay_wal(tail, state)
  end

  defp replay_wal(_rest, state), do: state

  @spec apply_entry(map(), term()) :: map()
  defp apply_entry(state, {:index, id, fields}), do: apply_index(state, id, fields)
  defp apply_entry(state, {:remove, id}), do: apply_remove(state, id)

  @spec wal_append(:file.io_device(), term()) :: :ok
  defp wal_append(dev, entry) do
    bin = :erlang.term_to_binary(entry)
    frame = <<byte_size(bin)::unsigned-big-integer-size(64), bin::binary>>
    :ok = :file.write(dev, frame)
    :ok = :file.sync(dev)
  end

  @spec do_snapshot(map()) :: map()
  defp do_snapshot(state) do
    tmp = state.snapshot_path <> ".tmp"
    bin = :erlang.term_to_binary(state.doc_index)
    {:ok, dev} = :file.open(tmp, [:write, :binary, :raw])
    :ok = :file.write(dev, bin)
    :ok = :file.sync(dev)
    :ok = :file.close(dev)
    :ok = :file.rename(tmp, state.snapshot_path)

    :ok = :file.close(state.wal)
    {:ok, trunc_dev} = :file.open(state.wal_path, [:write, :binary, :raw])
    :ok = :file.close(trunc_dev)
    {:ok, wal} = :file.open(state.wal_path, [:append, :binary, :raw])
    %{state | wal: wal}
  end

  # ── Index maintenance ─────────────────────────────────────────────────────

  @spec apply_index(map(), String.t(), map()) :: map()
  defp apply_index(state, id, fields) do
    state = apply_remove(state, id)

    per_field =
      Enum.reduce(fields, %{}, fn {field, text}, acc ->
        tokens = tokenize(text, state.stop_words)
        Map.put(acc, field, {count_tokens(tokens), length(tokens)})
      end)

    postings =
      Enum.reduce(per_field, state.postings, fn {field, {counts, _t}}, postings_acc ->
        Enum.reduce(counts, postings_acc, fn {token, count}, inner_acc ->
          put_posting(inner_acc, token, id, field, count)
        end)
      end)

    %{state | doc_index: Map.put(state.doc_index, id, per_field), postings: postings}
  end

  @spec apply_remove(map(), String.t()) :: map()
  defp apply_remove(state, id) do
    case Map.get(state.doc_index, id) do
      nil ->
        state

      per_field ->
        postings =
          Enum.reduce(per_field, state.postings, fn {field, {counts, _t}}, postings_acc ->
            Enum.reduce(counts, postings_acc, fn {token, _count}, inner_acc ->
              remove_posting(inner_acc, token, id, field)
            end)
          end)

        %{state | doc_index: Map.delete(state.doc_index, id), postings: postings}
    end
  end

  @spec build_postings(map()) :: map()
  defp build_postings(doc_index) do
    Enum.reduce(doc_index, %{}, fn {id, per_field}, postings_acc ->
      Enum.reduce(per_field, postings_acc, fn {field, {counts, _t}}, field_acc ->
        Enum.reduce(counts, field_acc, fn {token, count}, inner_acc ->
          put_posting(inner_acc, token, id, field, count)
        end)
      end)
    end)
  end

  @spec put_posting(map(), String.t(), String.t(), term(), pos_integer()) :: map()
  defp put_posting(postings, token, id, field, count) do
    doc_map = Map.get(postings, token, %{})
    field_map = Map.put(Map.get(doc_map, id, %{}), field, count)
    Map.put(postings, token, Map.put(doc_map, id, field_map))
  end

  @spec remove_posting(map(), String.t(), String.t(), term()) :: map()
  defp remove_posting(postings, token, id, field) do
    case Map.get(postings, token) do
      nil ->
        postings

      doc_map ->
        field_map = Map.delete(Map.get(doc_map, id, %{}), field)

        doc_map =
          if map_size(field_map) == 0 do
            Map.delete(doc_map, id)
          else
            Map.put(doc_map, id, field_map)
          end

        if map_size(doc_map) == 0 do
          Map.delete(postings, token)
        else
          Map.put(postings, token, doc_map)
        end
    end
  end

  # ── Query helpers ─────────────────────────────────────────────────────────

  @spec do_search(map(), String.t(), keyword()) :: [score_entry()]
  defp do_search(state, query, opts) do
    terms = Enum.uniq(tokenize(query, state.stop_words))
    total_docs = map_size(state.doc_index)

    scores = Enum.reduce(terms, %{}, &accumulate_term(&1, &2, state, total_docs))

    results =
      scores
      |> Enum.map(fn {id, score} -> %{id: id, score: score} end)
      |> Enum.sort_by(& &1.score, :desc)

    case Keyword.get(opts, :limit) do
      nil -> results
      limit -> Enum.take(results, limit)
    end
  end

  @spec accumulate_term(String.t(), map(), map(), non_neg_integer()) :: map()
  defp accumulate_term(term, scores, state, total_docs) do
    case Map.get(state.postings, term) do
      nil ->
        scores

      doc_map ->
        idf = :math.log(total_docs / map_size(doc_map))

        Enum.reduce(doc_map, scores, fn {id, field_map}, scores_acc ->
          add =
            Enum.reduce(field_map, +0.0, fn {field, count}, acc ->
              {_counts, total} = state.doc_index |> Map.fetch!(id) |> Map.fetch!(field)
              acc + count / total * idf
            end)

          Map.update(scores_acc, id, add, &(&1 + add))
        end)
    end
  end

  @spec do_suggest(map(), String.t(), non_neg_integer()) :: [String.t()]
  defp do_suggest(state, prefix, limit) do
    prefix = String.downcase(prefix)

    state.postings
    |> Map.keys()
    |> Enum.filter(&String.starts_with?(&1, prefix))
    |> Enum.sort_by(fn term -> map_size(Map.fetch!(state.postings, term)) end, :desc)
    |> Enum.take(limit)
  end

  # ── Tokenization ──────────────────────────────────────────────────────────

  @spec tokenize(String.t(), MapSet.t()) :: [String.t()]
  defp tokenize(text, stop_words) do
    text
    |> String.downcase()
    |> String.split(~r/[^a-z0-9]+/, trim: true)
    |> Enum.reject(&MapSet.member?(stop_words, &1))
  end

  @spec count_tokens([String.t()]) :: map()
  defp count_tokens(tokens) do
    Enum.reduce(tokens, %{}, fn token, acc ->
      Map.update(acc, token, 1, &(&1 + 1))
    end)
  end
end
