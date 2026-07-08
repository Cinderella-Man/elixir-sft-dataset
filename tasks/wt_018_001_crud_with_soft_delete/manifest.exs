# The harness dispatches via Plug.Test straight to SoftCrudWeb.Router (no
# ConnCase), so the tier-B archetype can no longer be inferred from the
# harness — state it explicitly: the kit compile + Repo/migrations boot are
# still required.
%{
  archetype: :phoenix_conncase,
  prefix: "SoftCrud",
  web_prefix: "SoftCrudWeb",
  otp_app: :soft_crud,
  db: :sqlite
}
