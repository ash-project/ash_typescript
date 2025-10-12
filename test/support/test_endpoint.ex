# SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
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
