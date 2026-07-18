  @doc """
  Reads the file at `path` and infers its schema.

  Behaves exactly as if the file's contents were passed to `infer_string/2`;
  accepts the same options.
  """
  @spec infer_file(Path.t(), keyword()) :: schema()
  def infer_file(path, opts \\ []) do
    path
    |> File.read!()
    |> infer_string(opts)
  end