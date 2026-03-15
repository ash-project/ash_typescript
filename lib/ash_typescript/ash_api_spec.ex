# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.AshApiSpec do
  @moduledoc """
  Standalone Spark DSL module for building a unified app-wide AshApiSpec.

  When the same resource appears in multiple domains' `typescript_rpc` blocks
  with different RPC actions, this module ensures all actions are merged into
  a single unified spec rather than each domain overwriting the previous one.

  ## Usage

      defmodule MyApp.AshApiSpec do
        use AshTypescript.AshApiSpec, otp_app: :my_app
      end
  """

  use Spark.Dsl,
    default_extensions: [extensions: [AshTypescript.AshApiSpec.Dsl]]
end
