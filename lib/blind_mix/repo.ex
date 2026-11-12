defmodule BlindMix.Repo do
  use Ecto.Repo,
    otp_app: :blind_mix,
    adapter: Ecto.Adapters.Postgres
end
