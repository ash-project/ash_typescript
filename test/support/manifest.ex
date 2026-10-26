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
    # Schemas authored in TypeScript, imported through `zod_import_into_generated`
    # / `valibot_import_into_generated` (config/config.exs).
    scalar AshTypescript.Test.CustomIdentifier, :string do
      zod "CustomZodSchemas.objectId"
      valibot "CustomValibotSchemas.objectId"
    end

    scalar AshTypescript.Test.ExternalCode, :string do
      typescript {AshTypescript.Test.ExternalCodeTs, :typescript, []}
      zod {AshTypescript.Test.ExternalCodeTs, :zod, []}
      valibot {AshTypescript.Test.ExternalCodeTs, :valibot, []}
    end

    # The schemas replace the object of the fields with one that checks ranges.
    map AshTypescript.Test.GeoPoint do
      type_name "GeoPoint"
      field :lat, :float, allow_nil?: false
      field :lng, :float, allow_nil?: false
      zod "NestedZodSchemas.geoPoint"
      valibot "NestedValibotSchemas.geoPoint"
    end

    # A declared type with a nested declared type and an embedded resource.
    map AshTypescript.Test.LineItem do
      type_name "LineItem"
      field :label, :string, allow_nil?: false
      field :price, AshMoney.Types.Money, allow_nil?: false
      field :meta, AshTypescript.Test.TaskMetadata
    end

    # A declared type with a non-embedded resource field, only returned.
    map AshTypescript.Test.TodoRef do
      field :todo, :struct, constraints: [instance_of: AshTypescript.Test.Todo]
    end
  end
end
