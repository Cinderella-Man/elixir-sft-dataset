  @spec persist_bucket(String.t(), String.t(), map()) :: :ok
  defp persist_bucket(root, name, keys) do
    path = Path.join(root, name <> @bucket_suffix)
    File.write!(path, :erlang.term_to_binary(keys))
    :ok
  end