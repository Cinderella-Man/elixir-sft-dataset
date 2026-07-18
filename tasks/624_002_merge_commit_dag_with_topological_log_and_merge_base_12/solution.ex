  # A commit is serialized as a deterministic, git-like text representation:
  #
  #     tree <tree-hash>
  #     parent <parent-hash>        (repeated, once per parent, in order)
  #     author <byte-size>
  #     <author>
  #     message <byte-size>
  #     <message>
  #
  # The byte-size headers let the author and message round-trip verbatim even
  # when they contain newlines. Identical inputs always yield identical bytes —
  # and therefore an identical hash — while any difference in the tree, in the
  # parents (including their order), in the author, or in the message changes
  # the bytes and thus the hash.
  @spec build_commit_object(hash(), [hash()], String.t(), String.t()) :: binary()
  defp build_commit_object(tree_hash, parents, message, author) do
    IO.iodata_to_binary([
      "tree ",
      tree_hash,
      "\n",
      Enum.map(parents, fn parent -> ["parent ", parent, "\n"] end),
      "author ",
      Integer.to_string(byte_size(author)),
      "\n",
      author,
      "\n",
      "message ",
      Integer.to_string(byte_size(message)),
      "\n",
      message,
      "\n"
    ])
  end