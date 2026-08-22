# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.Manifest do
  @moduledoc """
  Test Ash.Info.Manifest module for building unified app-wide spec.

  Domain (and resource) compilation ordering is handled by the manifest
  transformer itself, which calls `Code.ensure_compiled!/1` on every RPC
  resource before running reachability analysis (see
  `AshTypescript.Manifest.Transformers.BuildManifest`).
  """
  use AshTypescript.Manifest, otp_app: :ash_typescript
end
