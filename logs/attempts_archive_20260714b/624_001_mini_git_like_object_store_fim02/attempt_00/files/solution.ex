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