  defp parse_commit(binary) do
    {"tree " <> tree, rest} = split_line(binary)
    {parents, rest} = parse_parents(rest, [])
    {"author " <> author_size, rest} = split_line(rest)
    author_bytes = String.to_integer(author_size)
    <<author::binary-size(^author_bytes), "\n", rest::binary>> = rest
    {"message " <> message_size, rest} = split_line(rest)
    message_bytes = String.to_integer(message_size)
    <<message::binary-size(^message_bytes), "\n">> = rest

    %{tree: tree, parents: parents, author: author, message: message}
  end