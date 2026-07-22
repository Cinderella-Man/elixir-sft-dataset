defmodule Catalog do
  @moduledoc """
  In-memory catalog context supporting **dependency-ordered bulk creation**.

  Items in a single batch may reference other items in the *same* batch as their
  parent (via a temporary `"ref"` string). `bulk_create/2` resolves those
  references, creates entries in a valid topological order (parents before
  children), detects cycles, and — in partial mode — cascade-skips the
  transitive dependents of any item that fails.

  The store is backed by a named `Agent` (registered under this module) and holds
  items shaped as
  `%{id: integer, name: String.t(), ref: String.t() | nil, parent_id: integer | nil}`
  with auto-incrementing integer ids.
  """

  @typedoc "A stored catalog item."
  @type item :: %{
          id: integer(),
          name: String.t(),
          ref: String.t() | nil,
          parent_id: integer() | nil
        }

  @typedoc "Reason accompanying an `:error` result."
  @type reason ::
          {:validation, %{optional(String.t()) => [String.t()]}}
          | :duplicate_ref
          | :unknown_parent
          | :cycle

  @typedoc "A per-item, index-aware result tuple."
  @type result ::
          {non_neg_integer(), :ok, item() | :valid}
          | {non_neg_integer(), :error, reason()}
          | {non_neg_integer(), :skipped, non_neg_integer()}

  # ── Store ────────────────────────────────────────────────────────────────

  @doc """
  Start the backing `Agent`, registered under this module's name.
  """
  @spec start_link() :: Agent.on_start()
  def start_link do
    Agent.start_link(fn -> %{items: [], next_id: 1} end, name: __MODULE__)
  end

  @doc """
  Return all stored items, in creation order.
  """
  @spec all() :: [item()]
  def all do
    Agent.get(__MODULE__, fn state -> Enum.reverse(state.items) end)
  end

  @doc """
  Return the number of stored items.
  """
  @spec count() :: non_neg_integer()
  def count do
    Agent.get(__MODULE__, fn state -> length(state.items) end)
  end

  @doc """
  Fetch a single stored item by its `id`, or `nil` when absent.
  """
  @spec get(integer()) :: item() | nil
  def get(id) do
    Agent.get(__MODULE__, fn state -> Enum.find(state.items, &(&1.id == id)) end)
  end

  # ── Bulk create ────────────────────────────────────────────────────────────

  @doc """
  Bulk-create catalog entries, honouring in-batch parent references.

  Each attribute map may contain `"name"` (required, 1–100 chars), `"ref"`
  (optional in-batch identifier) and `"parent"` (optional reference to another
  item's `"ref"`).

  Options:

    * `:partial` — when `true`, create every creatable item and report bad items
      as errors with their transitive dependents `:skipped`. When `false`
      (default) the operation is all-or-nothing: if any item is not creatable,
      nothing is stored and `{:error, results}` is returned.

  Every result carries the zero-based input index. See `t:result/0`.
  """
  @spec bulk_create([map()], keyword()) :: {:ok, [result()]} | {:error, [result()]}
  def bulk_create(list, opts \\ []) do
    partial? = Keyword.get(opts, :partial, false)
    indexed = Enum.with_index(list)
    n = length(list)
    indices = Enum.to_list(0..(n - 1)//1)

    {ref_counts, ref_to_index} = build_ref_maps(indexed)
    {own_error, parent_index} = classify_items(indexed, ref_counts, ref_to_index)
    cyc = detect_cycles(indices, own_error, parent_index)
    status_map = build_status_map(indices, own_error, parent_index, cyc)

    all_creatable? = Enum.all?(indices, fn i -> Map.get(status_map, i) == :creatable end)
    store? = partial? or all_creatable?

    created_map =
      if store? do
        store_creatable(indices, status_map, indexed, parent_index)
      else
        %{}
      end

    results = build_results(indices, status_map, created_map, store?)

    if partial? or all_creatable? do
      {:ok, results}
    else
      {:error, results}
    end
  end

  # ── Reference maps ──────────────────────────────────────────────────────────

  @spec build_ref_maps([{map(), non_neg_integer()}]) ::
          {%{optional(String.t()) => pos_integer()},
           %{optional(String.t()) => non_neg_integer()}}
  defp build_ref_maps(indexed) do
    refs =
      for {attrs, i} <- indexed, ref = get_ref(attrs), is_binary(ref) do
        {ref, i}
      end

    counts =
      Enum.reduce(refs, %{}, fn {ref, _i}, acc ->
        Map.update(acc, ref, 1, &(&1 + 1))
      end)

    ref_to_index =
      for {ref, i} <- refs, Map.get(counts, ref) == 1, into: %{}, do: {ref, i}

    {counts, ref_to_index}
  end

  # ── Per-item classification ──────────────────────────────────────────────────

  @spec classify_items(
          [{map(), non_neg_integer()}],
          %{optional(String.t()) => pos_integer()},
          %{optional(String.t()) => non_neg_integer()}
        ) :: {%{non_neg_integer() => reason() | nil}, %{non_neg_integer() => nil | integer()}}
  defp classify_items(indexed, ref_counts, ref_to_index) do
    Enum.reduce(indexed, {%{}, %{}}, fn {attrs, i}, {own_error, parent_index} ->
      name = Map.get(attrs, "name")
      ref = get_ref(attrs)
      parent = get_parent(attrs)
      name_errs = validate_name(name)

      resolved_parent =
        if is_binary(parent), do: Map.get(ref_to_index, parent), else: nil

      error =
        cond do
          name_errs != [] -> {:validation, %{"name" => name_errs}}
          is_binary(ref) and Map.get(ref_counts, ref) > 1 -> :duplicate_ref
          is_binary(parent) and resolved_parent == nil -> :unknown_parent
          true -> nil
        end

      {Map.put(own_error, i, error), Map.put(parent_index, i, resolved_parent)}
    end)
  end

  @spec validate_name(term()) :: [String.t()]
  defp validate_name(name) when is_binary(name) do
    cond do
      String.trim(name) == "" -> ["can't be blank"]
      String.length(name) > 100 -> ["should be at most 100 character(s)"]
      true -> []
    end
  end

  defp validate_name(nil), do: ["can't be blank"]
  defp validate_name(_other), do: ["is invalid"]

  @spec get_ref(map()) :: String.t() | nil
  defp get_ref(attrs) do
    case Map.get(attrs, "ref") do
      ref when is_binary(ref) -> ref
      _other -> nil
    end
  end

  @spec get_parent(map()) :: String.t() | nil
  defp get_parent(attrs) do
    case Map.get(attrs, "parent") do
      parent when is_binary(parent) -> parent
      _other -> nil
    end
  end

  # ── Cycle detection (functional graph: out-degree ≤ 1) ───────────────────────

  @spec detect_cycles(
          [non_neg_integer()],
          %{non_neg_integer() => reason() | nil},
          %{non_neg_integer() => nil | integer()}
        ) :: MapSet.t(non_neg_integer())
  defp detect_cycles(indices, own_error, parent_index) do
    {_state, cyc} =
      Enum.reduce(indices, {%{}, MapSet.new()}, fn i, {state, cyc} ->
        if Map.has_key?(state, i) do
          {state, cyc}
        else
          walk(i, [], MapSet.new(), parent_index, own_error, state, cyc)
        end
      end)

    cyc
  end

  @spec walk(
          non_neg_integer(),
          [non_neg_integer()],
          MapSet.t(non_neg_integer()),
          %{non_neg_integer() => nil | integer()},
          %{non_neg_integer() => reason() | nil},
          map(),
          MapSet.t(non_neg_integer())
        ) :: {map(), MapSet.t(non_neg_integer())}
  defp walk(node, path, path_set, parent_index, own_error, state, cyc) do
    cond do
      Map.get(state, node) == :done ->
        {mark_done(path, state), cyc}

      MapSet.member?(path_set, node) ->
        {before, _rest} = Enum.split_while(path, &(&1 != node))
        cycle_nodes = before ++ [node]
        state = mark_done(path, state)
        cyc = Enum.reduce(cycle_nodes, cyc, fn nd, acc -> MapSet.put(acc, nd) end)
        {state, cyc}

      Map.get(own_error, node) != nil ->
        {mark_done([node | path], state), cyc}

      true ->
        new_path = [node | path]

        case Map.get(parent_index, node) do
          nil ->
            {mark_done(new_path, state), cyc}

          parent ->
            new_set = MapSet.put(path_set, node)
            walk(parent, new_path, new_set, parent_index, own_error, state, cyc)
        end
    end
  end

  @spec mark_done([non_neg_integer()], map()) :: map()
  defp mark_done(path, state) do
    Enum.reduce(path, state, fn node, acc -> Map.put(acc, node, :done) end)
  end

  # ── Status resolution ────────────────────────────────────────────────────────

  @spec build_status_map(
          [non_neg_integer()],
          %{non_neg_integer() => reason() | nil},
          %{non_neg_integer() => nil | integer()},
          MapSet.t(non_neg_integer())
        ) :: %{non_neg_integer() => :creatable | {:error, reason()} | {:skipped, non_neg_integer()}}
  defp build_status_map(indices, own_error, parent_index, cyc) do
    {status_map, _memo} =
      Enum.reduce(indices, {%{}, %{}}, fn i, {status_map, memo} ->
        {status, memo} = compute_status(i, own_error, parent_index, cyc, memo)
        {Map.put(status_map, i, status), memo}
      end)

    status_map
  end

  @spec compute_status(
          non_neg_integer(),
          %{non_neg_integer() => reason() | nil},
          %{non_neg_integer() => nil | integer()},
          MapSet.t(non_neg_integer()),
          map()
        ) :: {term(), map()}
  defp compute_status(i, own_error, parent_index, cyc, memo) do
    case Map.get(memo, i) do
      nil ->
        {status, memo} =
          cond do
            Map.get(own_error, i) != nil ->
              {{:error, Map.get(own_error, i)}, memo}

            MapSet.member?(cyc, i) ->
              {{:error, :cycle}, memo}

            true ->
              resolve_from_parent(i, own_error, parent_index, cyc, memo)
          end

        {status, Map.put(memo, i, status)}

      status ->
        {status, memo}
    end
  end

  @spec resolve_from_parent(
          non_neg_integer(),
          %{non_neg_integer() => reason() | nil},
          %{non_neg_integer() => nil | integer()},
          MapSet.t(non_neg_integer()),
          map()
        ) :: {term(), map()}
  defp resolve_from_parent(i, own_error, parent_index, cyc, memo) do
    case Map.get(parent_index, i) do
      nil ->
        {:creatable, memo}

      parent ->
        {parent_status, memo} = compute_status(parent, own_error, parent_index, cyc, memo)

        case parent_status do
          :creatable -> {:creatable, memo}
          _other -> {{:skipped, parent}, memo}
        end
    end
  end

  # ── Storage of creatable items in topological order ──────────────────────────

  @spec store_creatable(
          [non_neg_integer()],
          %{non_neg_integer() => term()},
          [{map(), non_neg_integer()}],
          %{non_neg_integer() => nil | integer()}
        ) :: %{non_neg_integer() => item()}
  defp store_creatable(indices, status_map, indexed, parent_index) do
    attrs_by_index = Map.new(indexed, fn {attrs, i} -> {i, attrs} end)

    ordered =
      indices
      |> Enum.filter(fn i -> Map.get(status_map, i) == :creatable end)
      |> Enum.sort_by(fn i -> {depth(i, parent_index), i} end)

    Agent.get_and_update(__MODULE__, fn state ->
      Enum.reduce(ordered, {%{}, state}, fn i, {created, st} ->
        attrs = Map.get(attrs_by_index, i)

        parent_id =
          case Map.get(parent_index, i) do
            nil -> nil
            parent -> Map.fetch!(created, parent).id
          end

        item = %{
          id: st.next_id,
          name: Map.get(attrs, "name"),
          ref: get_ref(attrs),
          parent_id: parent_id
        }

        new_state = %{st | items: [item | st.items], next_id: st.next_id + 1}
        {Map.put(created, i, item), new_state}
      end)
    end)
  end

  @spec depth(non_neg_integer(), %{non_neg_integer() => nil | integer()}) :: non_neg_integer()
  defp depth(i, parent_index) do
    case Map.get(parent_index, i) do
      nil -> 0
      parent -> 1 + depth(parent, parent_index)
    end
  end

  # ── Result assembly ────────────────────────────────────────────────────────

  @spec build_results(
          [non_neg_integer()],
          %{non_neg_integer() => term()},
          %{non_neg_integer() => item()},
          boolean()
        ) :: [result()]
  defp build_results(indices, status_map, created_map, store?) do
    Enum.map(indices, fn i ->
      case Map.get(status_map, i) do
        :creatable ->
          if store? do
            {i, :ok, Map.fetch!(created_map, i)}
          else
            {i, :ok, :valid}
          end

        {:error, reason} ->
          {i, :error, reason}

        {:skipped, ancestor} ->
          {i, :skipped, ancestor}
      end
    end)
  end
end