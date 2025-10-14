# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs.contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.TestEndpoint do
  @moduledoc """
  Minimal Phoenix endpoint for Tidewave MCP testing.
  """
  use Phoenix.Endpoint, otp_app: :ash_typescript

  # Add Tidewave plug conditionally (only if the module is loaded)
  if Code.ensure_loaded?(Tidewave) do
    plug(Tidewave)
  end
end
