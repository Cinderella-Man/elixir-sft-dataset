  defp all_object_keys(state, bucket) do
    obj_dir = objects_dir(state, bucket)

    case File.ls(obj_dir) do
      {:ok, files} ->
        files
        |> Enum.filter(&String.ends_with?(&1, ".meta"))
        |> Enum.map(fn filename ->
          filename
          |> String.trim_trailing(".meta")
          |> Base.url_decode64!(padding: false)
          |> :erlang.binary_to_term()
        end)

      {:error, :enoent} ->
        []
    end
  end