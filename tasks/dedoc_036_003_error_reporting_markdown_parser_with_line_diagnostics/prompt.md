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
defmodule MarkdownReport do
  @heading_re ~r/^(#+)\s+(.+?)\s*$/
  @item_re ~r/^-\s+\*\*(.+?)\*\*:\s+(.*?)(?:\s+\(([^)]*)\))?\s*$/
  @bullet_re ~r/^-\s+/

  def parse(markdown) when is_binary(markdown) do
    init = %{cats: [], current: nil, errors: [], seen: MapSet.new()}

    final =
      markdown
      |> String.split("\n")
      |> Enum.map(&String.trim_trailing/1)
      |> Enum.with_index(1)
      |> Enum.reduce(init, &step/2)
      |> flush()

    %{categories: Enum.reverse(final.cats), errors: Enum.reverse(final.errors)}
  end

  # ---------------------------------------------------------------------------
  # Per-line dispatch
  # ---------------------------------------------------------------------------

  defp step({line, idx}, acc) do
    case classify(line) do
      {:heading, title} -> handle_heading(title, line, idx, acc)
      :bad_heading -> add_error(acc, idx, line, :unsupported_heading)
      {:item, item} -> handle_item(item, line, idx, acc)
      :malformed_item -> add_error(acc, idx, line, :malformed_item)
      :ignore -> acc
    end
  end

  defp classify(line) do
    cond do
      caps = Regex.run(@heading_re, line, capture: :all_but_first) ->
        [hashes, title] = caps
        if String.length(hashes) == 2, do: {:heading, String.trim(title)}, else: :bad_heading

      caps = Regex.run(@item_re, line, capture: :all_but_first) ->
        {:item, build_item(caps)}

      Regex.match?(@bullet_re, line) ->
        :malformed_item

      true ->
        :ignore
    end
  end

  # ---------------------------------------------------------------------------
  # State transitions
  # ---------------------------------------------------------------------------

  defp handle_heading(title, line, idx, acc) do
    acc = flush(acc)

    if MapSet.member?(acc.seen, title) do
      %{acc | current: :suppressed}
      |> add_error(idx, line, :duplicate_category)
    else
      %{acc | current: %{category: title, items: []}, seen: MapSet.put(acc.seen, title)}
    end
  end

  defp handle_item(item, line, idx, acc) do
    case acc.current do
      %{} = node -> %{acc | current: %{node | items: [item | node.items]}}
      :suppressed -> acc
      nil -> add_error(acc, idx, line, :orphan_item)
    end
  end

  defp add_error(acc, idx, line, reason) do
    %{acc | errors: [%{line: idx, content: line, reason: reason} | acc.errors]}
  end

  # Flush the currently open category (if any) into the result list.
  defp flush(%{current: %{} = node} = acc) do
    %{acc | cats: [finalize(node) | acc.cats], current: nil}
  end

  defp flush(acc), do: %{acc | current: nil}

  defp finalize(%{category: category, items: items}) do
    %{category: category, items: Enum.reverse(items)}
  end

  # ---------------------------------------------------------------------------
  # Item building
  # ---------------------------------------------------------------------------

  defp build_item([name, description]), do: make(name, description, nil)
  defp build_item([name, description, raw]), do: make(name, description, raw)

  defp make(name, description, raw) do
    %{name: String.trim(name), description: String.trim(description), tags: tags(raw)}
  end

  defp tags(nil), do: []
  defp tags(""), do: []

  defp tags(raw) do
    raw
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end
end
```
