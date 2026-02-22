# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.AllowNilSometimesPresentErrorRouter do
  @moduledoc """
  Test router that mounts :provider_page asymmetrically across scopes.

  Admin scope has :provider as a path param, app scope does not.
  Since :provider has `allow_nil?: false` but is only a path param at one mount,
  the validation should raise an error.
  """
  use Phoenix.Router

  scope "/admin", as: :admin do
    get("/auth/providers/:provider", AshTypescript.Test.SessionController, :provider_page)
  end

  scope "/app", as: :app do
    get("/auth/providers", AshTypescript.Test.SessionController, :provider_page)
  end
end
