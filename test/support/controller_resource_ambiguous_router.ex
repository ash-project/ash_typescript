# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.ControllerResourceAmbiguousRouter do
  @moduledoc """
  Test router where a controller is mounted at multiple scopes WITHOUT `as:` options.
  This should cause an error during codegen.
  """
  use Phoenix.Router

  scope "/admin" do
    get("/auth", AshTypescript.Test.SessionController, :auth)
  end

  scope "/app" do
    get("/auth", AshTypescript.Test.SessionController, :auth)
  end
end
