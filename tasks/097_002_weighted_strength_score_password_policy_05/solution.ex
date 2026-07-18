  defp build_config(context) do
    %{
      username: Map.fetch!(context, :username),
      min_length: Map.get(context, :min_length, @default_min_length),
      min_score: Map.get(context, :min_score, @default_min_score),
      common_passwords: Map.get(context, :common_passwords, @default_common_passwords),
      max_username_similarity:
        Map.get(context, :max_username_similarity, @default_max_username_similarity)
    }
  end