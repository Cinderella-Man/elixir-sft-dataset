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