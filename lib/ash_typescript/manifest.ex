# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Manifest do
  @moduledoc """
  Standalone Spark DSL module for building a unified app-wide Ash.Info.Manifest.

  When the same resource appears in multiple domains' `typescript_rpc` blocks
  with different RPC actions, this module ensures all actions are merged into
  a single unified spec rather than each domain overwriting the previous one.

  ## Usage

      defmodule MyApp.Ash.Info.Manifest do
        use AshTypescript.Manifest, otp_app: :my_app
      end
  """

  use Spark.Dsl,
    default_extensions: [extensions: [AshTypescript.Manifest.Dsl]]
end
