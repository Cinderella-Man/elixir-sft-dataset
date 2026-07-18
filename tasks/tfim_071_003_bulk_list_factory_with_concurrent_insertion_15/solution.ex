  test "params_for(:post) resolves the association to an integer user_id" do
    params = Factory.params_for(:post)
    assert is_integer(params.user_id)
    refute Map.has_key?(params, :id)
  end