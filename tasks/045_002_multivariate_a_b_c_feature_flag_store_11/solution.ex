  defp pick_variant(flag_name, user_id, variants) do
    bucket = :erlang.phash2({flag_name, user_id}, 100)
    select(variants, bucket, 0)
  end