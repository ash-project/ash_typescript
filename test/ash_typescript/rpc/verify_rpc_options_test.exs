# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# Resources are defined at top level so Spark DSL fully compiles them before
# the inline domains reference them.

defmodule AshTypescript.Rpc.VerifyRpcOptionsTest.Settings do
  @moduledoc false
  use Ash.Resource, data_layer: :embedded, extensions: [AshTypescript.Resource]

  typescript do
    type_name "VerifyOptionsSettings"
  end

  attributes do
    attribute :theme, :string, public?: true
  end

  calculations do
    calculate :display_theme, :string, expr(theme), public?: true
  end
end

defmodule AshTypescript.Rpc.VerifyRpcOptionsTest.Item do
  @moduledoc false
  use Ash.Resource, domain: nil, extensions: [AshTypescript.Resource]

  typescript do
    type_name "VerifyOptionsItem"
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
    attribute :source_id, :uuid, public?: true
  end

  actions do
    defaults [:read]
  end
end

defmodule AshTypescript.Rpc.VerifyRpcOptionsTest.Source do
  @moduledoc false
  use Ash.Resource, domain: nil, extensions: [AshTypescript.Resource]

  typescript do
    type_name "VerifyOptionsSource"
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, public?: true
    attribute :settings, AshTypescript.Rpc.VerifyRpcOptionsTest.Settings, public?: true
  end

  relationships do
    has_many :items, AshTypescript.Rpc.VerifyRpcOptionsTest.Item,
      destination_attribute: :source_id,
      public?: true
  end

  calculations do
    calculate :display_name, :string, expr(name), public?: true
  end

  aggregates do
    count :items_count, :items, public?: true
  end

  actions do
    defaults [:read]

    read :read_with_meta do
      metadata :total_count, :integer
      metadata :cache_status, :string
    end
  end
end

defmodule AshTypescript.Rpc.VerifyRpcOptionsTest do
  @moduledoc """
  Integration tests for the `show_metadata` and `allowed_loads`/`denied_loads`
  existence checks in `AshTypescript.Manifest.Verifiers.VerifyRpc`.
  """
  use ExUnit.Case, async: false

  alias AshTypescript.Rpc.VerifyRpcOptionsTest.Source

  describe "show_metadata validation" do
    test "rejects metadata fields the action does not define" do
      defmodule BadMetadataDomain do
        use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource Source do
            rpc_action :list_with_meta, :read_with_meta, show_metadata: [:total_count, :has_more]
          end
        end

        resources do
          resource Source
        end
      end

      assert {:error, message} = silent_verify_for_domains([BadMetadataDomain])
      assert message =~ "show_metadata contains unknown metadata fields"
      assert message =~ ":has_more"
      assert message =~ "list_with_meta"
    end

    test "accepts metadata fields the action defines" do
      defmodule GoodMetadataDomain do
        use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource Source do
            rpc_action :list_with_meta_ok, :read_with_meta,
              show_metadata: [:total_count, :cache_status]
          end
        end

        resources do
          resource Source
        end
      end

      assert :ok = silent_verify_for_domains([GoodMetadataDomain])
    end
  end

  describe "allowed_loads / denied_loads validation" do
    test "rejects load paths that don't exist on the resource" do
      defmodule BadAllowedLoadsDomain do
        use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource Source do
            rpc_action :list_bad_loads, :read, allowed_loads: [:nonexistent]
          end
        end

        resources do
          resource Source
        end
      end

      assert {:error, message} = silent_verify_for_domains([BadAllowedLoadsDomain])
      assert message =~ "allowed_loads contains invalid load paths"
      assert message =~ "nonexistent"
    end

    test "rejects nested load paths that don't exist on the relationship destination" do
      defmodule BadNestedDeniedLoadsDomain do
        use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource Source do
            rpc_action :list_bad_nested, :read, denied_loads: [items: [:bogus]]
          end
        end

        resources do
          resource Source
        end
      end

      assert {:error, message} = silent_verify_for_domains([BadNestedDeniedLoadsDomain])
      assert message =~ "denied_loads contains invalid load paths"
      assert message =~ "items.bogus"
    end

    test "rejects plain attributes (never load paths)" do
      defmodule AttributeLoadDomain do
        use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource Source do
            rpc_action :list_attr_load, :read, allowed_loads: [:name]
          end
        end

        resources do
          resource Source
        end
      end

      assert {:error, message} = silent_verify_for_domains([AttributeLoadDomain])
      assert message =~ "allowed_loads contains invalid load paths"
      assert message =~ "name"
    end

    test "rejects unknown fields nested under an embedded attribute" do
      defmodule BadEmbeddedLoadsDomain do
        use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource Source do
            rpc_action :list_bad_embedded, :read, allowed_loads: [settings: [:nope]]
          end
        end

        resources do
          resource Source
        end
      end

      assert {:error, message} = silent_verify_for_domains([BadEmbeddedLoadsDomain])
      assert message =~ "allowed_loads contains invalid load paths"
      assert message =~ "settings.nope"
    end

    test "accepts relationships, calculations, aggregates, and valid nested paths" do
      defmodule GoodLoadsDomain do
        use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

        typescript_rpc do
          resource Source do
            rpc_action :list_good_loads, :read,
              allowed_loads: [:display_name, :items_count, settings: [:display_theme], items: []]
          end
        end

        resources do
          resource Source
        end
      end

      assert :ok = silent_verify_for_domains([GoodLoadsDomain])
    end
  end

  # Compiling the throwaway manifest module makes Elixir's parallel checker echo
  # raised DslErrors (and RPC config IO.warn output) to stderr, so silence it.
  defp silent_verify_for_domains(domains) do
    {result, _stderr} =
      ExUnit.CaptureIO.with_io(:standard_error, fn ->
        AshTypescript.Manifest.verify_for_domains(domains)
      end)

    result
  end
end
