defmodule MarkdownOutline do
  @moduledoc """
  Parses a Markdown document into a nested outline tree driven by ATX heading depth.

  The parser recognises two kinds of significant lines:

    * headings — `# Title` through `###### Title`, where the number of leading `#`
      characters is the node's `level`;
    * bullet items — `- **Item Name**: description (tag1, tag2)`, where the trailing
      parenthesised tag list is optional.

  Nesting is *relative*, not absolute: a heading deeper than the currently open heading
  becomes its child, regardless of how many levels were skipped (a `#` followed directly
  by a `###` still yields a parent/child pair). A heading at the same or a shallower level
  closes the open branch and starts a new sibling of the nearest ancestor with a smaller
  level.

  Items attach to the deepest currently open heading. Items appearing before the first
  heading are discarded, and every other line (blank lines, indented sub-bullets,
  non-matching bullets, headings with seven or more `#` characters) is ignored.

  ## Example

      iex> MarkdownOutline.parse("# Parent\\n- **p**: pd (a, b)\\n### Child\\n")
      [
        %{
          title: "Parent",
          level: 1,
          items: [%{name: "p", description: "pd", tags: ["a", "b"]}],
          children: [%{title: "Child", level: 3, items: [], children: []}]
        }
      ]
  """

  @heading_regex ~r/^(\#{1,6})\s+(\S.*)$/
  @item_regex ~r/^-\s+\*\*(.+?)\*\*:\s*(.*)$/
  @tags_regex ~r/^(.*?)\s*\(([^()]*)\)$/

  @typedoc "A single bullet item attached to an outline node."
  @type item :: %{name: String.t(), description: String.t(), tags: [String.t()]}

  @typedoc "An outline node: a heading with its items and nested child headings."
  @type node_map :: %{
          title: String.t(),
          level: pos_integer(),
          items: [item()],
          children: [node_map()]
        }

  @doc """
  Parses `markdown` into a list of top-level outline nodes, in document order.

  Each node is a map with `:title`, `:level`, `:items` and `:children` keys. Returns `[]`
  for an empty (or heading-free) document.

  ## Examples

      iex> MarkdownOutline.parse("")
      []

      iex> MarkdownOutline.parse("## Solo")
      [%{title: "Solo", level: 2, items: [], children: []}]
  """
  @spec parse(binary()) :: [node_map()]
  def parse(markdown) when is_binary(markdown) do
    markdown
    |> String.split(~r/\r\n|\r|\n/)
    |> Enum.reduce({[], []}, &handle_line/2)
    |> close_all()
  end

  # State is `{stack, done}`:
  #   * `stack` — open nodes from deepest to shallowest (each with reversed items/children);
  #   * `done` — completed top-level nodes, in reverse document order.
  @spec handle_line(String.t(), {[map()], [map()]}) :: {[map()], [map()]}
  defp handle_line(line, {stack, done} = state) do
    trimmed = String.trim_trailing(line)

    cond do
      captures = Regex.run(@heading_regex, trimmed) ->
        [_, hashes, title] = captures
        open_heading(byte_size(hashes), String.trim(title), stack, done)

      captures = Regex.run(@item_regex, trimmed) ->
        [_, name, rest] = captures
        add_item(build_item(name, rest), stack, done)

      true ->
        state
    end
  end

  @spec open_heading(pos_integer(), String.t(), [map()], [map()]) :: {[map()], [map()]}
  defp open_heading(level, title, stack, done) do
    {stack, done} = pop_until_parent(level, stack, done)
    node = %{title: title, level: level, items: [], children: []}
    {[node | stack], done}
  end

  # Close every open node whose level is greater than or equal to the incoming level, so
  # that the head of the stack (if any) is a strict ancestor of the new heading.
  @spec pop_until_parent(pos_integer(), [map()], [map()]) :: {[map()], [map()]}
  defp pop_until_parent(level, [%{level: open_level} | _] = stack, done)
       when open_level >= level do
    {stack, done} = close_top(stack, done)
    pop_until_parent(level, stack, done)
  end

  defp pop_until_parent(_level, stack, done), do: {stack, done}

  # Finalise the deepest open node, attaching it to its parent or to the finished roots.
  @spec close_top([map()], [map()]) :: {[map()], [map()]}
  defp close_top([node | rest], done) do
    finished = finalize(node)

    case rest do
      [parent | ancestors] ->
        parent = %{parent | children: [finished | parent.children]}
        {[parent | ancestors], done}

      [] ->
        {[], [finished | done]}
    end
  end

  @spec close_all({[map()], [map()]}) :: [node_map()]
  defp close_all({[], done}), do: Enum.reverse(done)

  defp close_all({stack, done}) do
    close_all(close_top(stack, done))
  end

  @spec add_item(item(), [map()], [map()]) :: {[map()], [map()]}
  defp add_item(_item, [], done), do: {[], done}

  defp add_item(item, [node | rest], done) do
    {[%{node | items: [item | node.items]} | rest], done}
  end

  @spec build_item(String.t(), String.t()) :: item()
  defp build_item(name, rest) do
    {description, tags} = split_tags(String.trim(rest))
    %{name: String.trim(name), description: description, tags: tags}
  end

  @spec split_tags(String.t()) :: {String.t(), [String.t()]}
  defp split_tags(text) do
    case Regex.run(@tags_regex, text) do
      [_, description, tag_list] -> {String.trim(description), parse_tags(tag_list)}
      nil -> {text, []}
    end
  end

  @spec parse_tags(String.t()) :: [String.t()]
  defp parse_tags(tag_list) do
    tag_list
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  # Reverse the accumulators so items and children come out in document order.
  @spec finalize(map()) :: node_map()
  defp finalize(node) do
    %{node | items: Enum.reverse(node.items), children: Enum.reverse(node.children)}
  end
end