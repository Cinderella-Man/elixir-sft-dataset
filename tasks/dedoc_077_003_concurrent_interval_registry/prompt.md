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
defmodule IntervalRegistry do
  use GenServer

  # -------------------------------------------------------------------------
  # Client API
  # -------------------------------------------------------------------------

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, :ok, opts)

  def stop(server), do: GenServer.stop(server)

  def insert(server, {s, f}) when is_integer(s) and is_integer(f) and s <= f do
    GenServer.call(server, {:insert, s, f})
  end

  def remove(server, id) when is_integer(id), do: GenServer.call(server, {:remove, id})

  def overlapping(server, {s, f}) when is_integer(s) and is_integer(f) and s <= f do
    GenServer.call(server, {:overlapping, s, f})
  end

  def enclosing(server, point) when is_integer(point) do
    GenServer.call(server, {:enclosing, point})
  end

  def stab_count(server, point) when is_integer(point) do
    GenServer.call(server, {:stab_count, point})
  end

  def size(server), do: GenServer.call(server, :size)

  # -------------------------------------------------------------------------
  # Server callbacks
  # -------------------------------------------------------------------------

  @impl true
  def init(:ok), do: {:ok, %{tree: nil, next_id: 1, entries: %{}}}

  @impl true
  def handle_call({:insert, s, f}, _from, state) do
    id = state.next_id
    tree = t_insert(state.tree, s, f, id)

    new_state = %{
      state
      | tree: tree,
        next_id: id + 1,
        entries: Map.put(state.entries, id, {s, f})
    }

    {:reply, {:ok, id}, new_state}
  end

  def handle_call({:remove, id}, _from, state) do
    case Map.fetch(state.entries, id) do
      {:ok, {s, f}} ->
        tree = t_delete(state.tree, s, f, id)
        {:reply, :ok, %{state | tree: tree, entries: Map.delete(state.entries, id)}}

      :error ->
        {:reply, {:error, :not_found}, state}
    end
  end

  def handle_call({:overlapping, qs, qf}, _from, state) do
    {:reply, Enum.sort(t_overlapping(state.tree, qs, qf, [])), state}
  end

  def handle_call({:enclosing, point}, _from, state) do
    {:reply, Enum.sort(t_enclosing(state.tree, point, [])), state}
  end

  def handle_call({:stab_count, point}, _from, state) do
    {:reply, t_stab_count(state.tree, point, 0), state}
  end

  def handle_call(:size, _from, state) do
    {:reply, map_size(state.entries), state}
  end

  # -------------------------------------------------------------------------
  # Internal augmented AVL tree, keyed by {s, f, id}
  # -------------------------------------------------------------------------

  defp t_height(nil), do: 0
  defp t_height(%{height: h}), do: h

  defp t_node(s, f, id, left, right) do
    h = 1 + max(t_height(left), t_height(right))
    mf = f |> t_max_child(left) |> t_max_child(right)
    %{s: s, f: f, id: id, max_finish: mf, height: h, left: left, right: right}
  end

  defp t_max_child(acc, nil), do: acc
  defp t_max_child(acc, %{max_finish: mf}), do: max(acc, mf)

  defp t_key(%{s: s, f: f, id: id}), do: {s, f, id}

  defp t_bf(nil), do: 0
  defp t_bf(%{left: l, right: r}), do: t_height(l) - t_height(r)

  defp t_rotate_right(%{left: %{} = y} = x) do
    t_node(y.s, y.f, y.id, y.left, t_node(x.s, x.f, x.id, y.right, x.right))
  end

  defp t_rotate_left(%{right: %{} = y} = x) do
    t_node(y.s, y.f, y.id, t_node(x.s, x.f, x.id, x.left, y.left), y.right)
  end

  defp t_rebalance(node) do
    bf = t_bf(node)

    cond do
      bf > 1 ->
        node =
          if t_bf(node.left) < 0 do
            t_node(node.s, node.f, node.id, t_rotate_left(node.left), node.right)
          else
            node
          end

        t_rotate_right(node)

      bf < -1 ->
        node =
          if t_bf(node.right) > 0 do
            t_node(node.s, node.f, node.id, node.left, t_rotate_right(node.right))
          else
            node
          end

        t_rotate_left(node)

      true ->
        node
    end
  end

  defp t_insert(nil, s, f, id), do: t_node(s, f, id, nil, nil)

  defp t_insert(node, s, f, id) do
    updated =
      if {s, f, id} < t_key(node) do
        t_node(node.s, node.f, node.id, t_insert(node.left, s, f, id), node.right)
      else
        t_node(node.s, node.f, node.id, node.left, t_insert(node.right, s, f, id))
      end

    t_rebalance(updated)
  end

  defp t_delete(nil, _s, _f, _id), do: nil

  defp t_delete(node, s, f, id) do
    key = {s, f, id}
    nkey = t_key(node)

    cond do
      key < nkey ->
        t_rebalance(t_node(node.s, node.f, node.id, t_delete(node.left, s, f, id), node.right))

      key > nkey ->
        t_rebalance(t_node(node.s, node.f, node.id, node.left, t_delete(node.right, s, f, id)))

      true ->
        t_delete_here(node)
    end
  end

  defp t_delete_here(%{left: nil, right: r}), do: r
  defp t_delete_here(%{left: l, right: nil}), do: l

  defp t_delete_here(%{left: l, right: r}) do
    succ = t_min(r)
    nr = t_delete(r, succ.s, succ.f, succ.id)
    t_rebalance(t_node(succ.s, succ.f, succ.id, l, nr))
  end

  defp t_min(%{left: nil} = node), do: node
  defp t_min(%{left: l}), do: t_min(l)

  defp t_overlapping(nil, _qs, _qf, acc), do: acc
  defp t_overlapping(%{max_finish: mf}, qs, _qf, acc) when mf < qs, do: acc

  defp t_overlapping(%{s: s, f: f, left: l, right: r}, qs, qf, acc) do
    acc = if s <= qf and f >= qs, do: [{s, f} | acc], else: acc
    acc = t_overlapping(l, qs, qf, acc)

    if s <= qf, do: t_overlapping(r, qs, qf, acc), else: acc
  end

  defp t_enclosing(nil, _point, acc), do: acc
  defp t_enclosing(%{max_finish: mf}, point, acc) when mf < point, do: acc

  defp t_enclosing(%{s: s, f: f, left: l, right: r}, point, acc) do
    acc = if s <= point and point <= f, do: [{s, f} | acc], else: acc
    acc = t_enclosing(l, point, acc)

    if s <= point, do: t_enclosing(r, point, acc), else: acc
  end

  defp t_stab_count(nil, _point, acc), do: acc
  defp t_stab_count(%{max_finish: mf}, point, acc) when mf < point, do: acc

  defp t_stab_count(%{s: s, f: f, left: l, right: r}, point, acc) do
    acc = if s <= point and point <= f, do: acc + 1, else: acc
    acc = t_stab_count(l, point, acc)

    if s <= point, do: t_stab_count(r, point, acc), else: acc
  end
end
```
