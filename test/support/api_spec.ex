# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.ApiSpec do
  @moduledoc """
  Test AshApiSpec module for building unified app-wide spec.

  The require statements ensure domains (and their resources) are
  compiled before the transformer runs reachability analysis.
  """
  require AshTypescript.Test.Domain
  require AshTypescript.Test.SecondDomain

  use AshTypescript.AshApiSpec, otp_app: :ash_typescript
end
