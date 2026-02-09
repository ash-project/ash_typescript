# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.ControllerResourceMultiMountRouter do
  @moduledoc """
  Test router where a controller is mounted at multiple scopes with `as:` options.
  """
  use Phoenix.Router

  scope "/admin", as: :admin do
    get("/auth", AshTypescript.Test.SessionController, :auth)
    get("/auth/providers/:provider", AshTypescript.Test.SessionController, :provider_page)
    post("/auth/login", AshTypescript.Test.SessionController, :login)
    post("/auth/logout", AshTypescript.Test.SessionController, :logout)
    patch("/auth/providers/:provider", AshTypescript.Test.SessionController, :update_provider)
    post("/echo", AshTypescript.Test.SessionController, :echo_params)
  end

  scope "/app", as: :app do
    get("/auth", AshTypescript.Test.SessionController, :auth)
    get("/auth/providers/:provider", AshTypescript.Test.SessionController, :provider_page)
    post("/auth/login", AshTypescript.Test.SessionController, :login)
    post("/auth/logout", AshTypescript.Test.SessionController, :logout)
    patch("/auth/providers/:provider", AshTypescript.Test.SessionController, :update_provider)
    post("/echo", AshTypescript.Test.SessionController, :echo_params)
  end
end
