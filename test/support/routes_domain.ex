# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.ControllerResourceDomain do
  @moduledoc """
  Test domain for controller resource extension testing.
  """
  use Ash.Domain,
    otp_app: :ash_typescript

  resources do
    resource AshTypescript.Test.Session
  end
end
