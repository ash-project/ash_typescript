# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.ControllerResourceTestRouter do
  @moduledoc """
  Test Phoenix router for controller resource extension testing.
  Maps session management controller actions to conventional URL paths.
  """
  use Phoenix.Router

  scope "/" do
    get("/auth", AshTypescript.Test.SessionController, :auth)
    get("/auth/providers/:provider", AshTypescript.Test.SessionController, :provider_page)
    get("/search", AshTypescript.Test.SessionController, :search)
    post("/auth/login", AshTypescript.Test.SessionController, :login)
    post("/auth/logout", AshTypescript.Test.SessionController, :logout)
    patch("/auth/providers/:provider", AshTypescript.Test.SessionController, :update_provider)
    get("/profile", AshTypescript.Test.SessionController, :profile)
    post("/raise-error", AshTypescript.Test.SessionController, :raise_error)
    post("/echo", AshTypescript.Test.SessionController, :echo_params)
    post("/register", AshTypescript.Test.SessionController, :register)
    post("/tasks", AshTypescript.Test.SessionController, :create_task)
  end
end
