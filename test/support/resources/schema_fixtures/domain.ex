# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.SchemaFixtures.Holder do
  @moduledoc false
  # Makes the ZodOrder embedded resources reachable from an entrypoint, so the
  # schema fixtures manifest decorates them.
  use Ash.Resource,
    domain: AshTypescript.Test.SchemaFixtures.Domain,
    extensions: [AshTypescript.Resource]

  typescript do
    type_name "SchemaFixturesHolder"
  end

  actions do
    action :accept_node, :boolean do
      argument :node, AshTypescript.Test.ZodOrder.NodeA

      run fn _input, _context -> {:ok, true} end
    end
  end
end

defmodule AshTypescript.Test.SchemaFixtures.Domain do
  @moduledoc """
  Schema-generation fixtures kept out of the app's manifest: `NestedArrayConstraints`
  and the `ZodOrder` embedded resources. Codegen names fields only from decorated
  manifest nodes, so tests build this domain's manifest with `manifest/0` and run
  codegen inside `AshTypescript.with_manifest/2`.
  """
  use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

  typescript_rpc do
    resource AshTypescript.Test.NestedArrayConstraints do
      rpc_action :validate_nested_array_constraints, :validate
    end

    resource AshTypescript.Test.SchemaFixtures.Holder do
      rpc_action :accept_zod_order_node, :accept_node
    end
  end

  resources do
    resource AshTypescript.Test.NestedArrayConstraints
    resource AshTypescript.Test.SchemaFixtures.Holder
  end

  @doc "The decorated manifest of this domain, plus `domains` when a test mixes in app resources."
  def manifest(domains \\ []),
    do: AshTypescript.Test.InlineManifest.build!(domains: domains ++ [__MODULE__])
end
