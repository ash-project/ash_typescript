# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.ControllerResourceNestedScopeRouter do
  @moduledoc """
  Test router with nested scopes and repeated mounts, to verify path-param
  extraction and scope-prefix resolution beyond the flat multi-mount shape.
  """
  use Phoenix.Router

  scope "/api", as: :api do
    scope "/v1", as: :v1 do
      get("/auth", AshTypescript.Test.SessionController, :auth)
      get("/auth/providers/:provider", AshTypescript.Test.SessionController, :provider_page)
    end

    scope "/v2", as: :v2 do
      get("/auth", AshTypescript.Test.SessionController, :auth)
      get("/auth/providers/:provider", AshTypescript.Test.SessionController, :provider_page)
    end
  end

  scope "/legacy", as: :legacy do
    get("/auth", AshTypescript.Test.SessionController, :auth)
    get("/auth/providers/:provider", AshTypescript.Test.SessionController, :provider_page)
  end
end
