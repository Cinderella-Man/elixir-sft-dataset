  test "params_for returns a plain map without :id" do
    params = Factory.params_for(:user)
    assert is_map(params)
    refute is_struct(params)
    refute Map.has_key?(params, :id)
    assert is_binary(params.email)
  end