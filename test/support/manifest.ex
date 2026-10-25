# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.Manifest do
  @moduledoc """
  Test Ash.Info.Manifest module for building unified app-wide spec. It also
  lists the typed controller and channel fixtures used by codegen snapshots
  (the manifest options are the only source of typed modules).

  Domain (and resource) compilation ordering is handled by the manifest
  transformer itself, which calls `Code.ensure_compiled!/1` on every RPC
  resource before running reachability analysis (see
  `AshTypescript.Manifest.Transformers.BuildManifest`).
  """
  use AshTypescript.Manifest,
    otp_app: :ash_typescript,
    typed_controllers: [AshTypescript.Test.Session],
    typed_channels: [
      AshTypescript.Test.OrgChannel,
      AshTypescript.Test.ContentFeedChannel,
      AshTypescript.Test.ModerationChannel,
      AshTypescript.Test.FullActivityChannel,
      AshTypescript.Test.TrackerChannel
    ]

  custom_types do
    scalar AshTypescript.Test.CustomIdentifier, :string

    scalar AshTypescript.Test.ExternalCode, :string,
      typescript: {AshTypescript.Test.ExternalCodeTs, :typescript, []}
  end
end
