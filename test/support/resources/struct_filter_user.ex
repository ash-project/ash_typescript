# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.StructFilterUser do
  @moduledoc """
  Test resource for `AshTypescript.Rpc.StructFieldFilteringTest`. Carries a mix
  of public and private attributes plus a self-struct calculation so the test
  can assert that `ResultProcessor` filters non-public fields from struct
  values pulled out of the manifest.

  Registered in `AshTypescript.Test.Domain` so it lives in the production test
  manifest — no runtime resource override needed.
  """
  use Ash.Resource,
    domain: AshTypescript.Test.Domain,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshTypescript.Resource]

  typescript do
    type_name "StructFilterUser"
  end

  ets do
    private? true
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
    attribute :email, :string, public?: true
    attribute :secret, :string, public?: false
    attribute :internal_notes, :string, public?: false
  end

  calculations do
    calculate :self_struct, :struct, fn records, _ -> records end do
      constraints instance_of: __MODULE__
      public? true
    end
  end

  actions do
    defaults [:read]
  end
end
