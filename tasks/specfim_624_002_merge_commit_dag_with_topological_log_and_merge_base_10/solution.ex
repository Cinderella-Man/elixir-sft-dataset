  @spec parse_commit(binary()) :: %{
          tree: hash(),
          parents: [hash()],
          author: String.t(),
          message: String.t()
        }