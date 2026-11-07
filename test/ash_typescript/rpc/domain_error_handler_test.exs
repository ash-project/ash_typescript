# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

# Resources are defined at top level so Spark DSL fully compiles them before
# the inline domains reference them. They have no domain of their own
# (`domain: nil`): ash_rpc runs each action in its entrypoint's domain.
defmodule AshTypescript.Rpc.DomainErrorHandlerTest.Handler do
  @moduledoc false
  def handle_error(error, _context), do: %{error | message: "handled by module"}

  def handle(error, _context, label), do: %{error | message: "handled by #{label}"}
end

defmodule AshTypescript.Rpc.DomainErrorHandlerTest.MfaNote do
  @moduledoc false
  use Ash.Resource,
    domain: nil,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshTypescript.Resource]

  typescript do
    type_name "MfaHandlerNote"
  end

  attributes do
    uuid_primary_key :id
    attribute :body, :string, allow_nil?: false, public?: true
  end

  actions do
    defaults [:read, create: [:body]]
  end
end

defmodule AshTypescript.Rpc.DomainErrorHandlerTest.ModuleNote do
  @moduledoc false
  use Ash.Resource,
    domain: nil,
    data_layer: Ash.DataLayer.Ets,
    extensions: [AshTypescript.Resource]

  typescript do
    type_name "ModuleHandlerNote"
  end

  attributes do
    uuid_primary_key :id
    attribute :body, :string, allow_nil?: false, public?: true
  end

  actions do
    defaults [:read, create: [:body]]
  end
end

defmodule AshTypescript.Rpc.DomainErrorHandlerTest.MfaDomain do
  @moduledoc false
  use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

  typescript_rpc do
    error_handler {AshTypescript.Rpc.DomainErrorHandlerTest.Handler, :handle, ["mfa"]}

    resource AshTypescript.Rpc.DomainErrorHandlerTest.MfaNote do
      rpc_action :create_mfa_note, :create
    end
  end

  resources do
    resource AshTypescript.Rpc.DomainErrorHandlerTest.MfaNote
  end
end

defmodule AshTypescript.Rpc.DomainErrorHandlerTest.ModuleDomain do
  @moduledoc false
  use Ash.Domain, otp_app: :ash_typescript, extensions: [AshTypescript.Rpc]

  typescript_rpc do
    error_handler AshTypescript.Rpc.DomainErrorHandlerTest.Handler

    resource AshTypescript.Rpc.DomainErrorHandlerTest.ModuleNote do
      rpc_action :create_module_note, :create
    end
  end

  resources do
    resource AshTypescript.Rpc.DomainErrorHandlerTest.ModuleNote
  end
end

defmodule AshTypescript.Rpc.DomainErrorHandlerTest do
  # A domain's `typescript_rpc` `error_handler`, in both forms, applied by
  # `AshTypescript.RpcProfile` to a failing `AshRpc.run_action/4`.
  use ExUnit.Case, async: true

  alias AshTypescript.Rpc.DomainErrorHandlerTest.{Handler, MfaDomain, ModuleDomain}
  alias AshTypescript.RpcProfile

  @moduletag :ash_typescript

  setup_all do
    %{
      manifest:
        AshTypescript.Test.InlineManifest.build!(domains: [MfaDomain, ModuleDomain], body: nil)
    }
  end

  defp run(manifest, action) do
    conn = %Plug.Conn{assigns: %{ash_actor: nil, ash_tenant: nil}}

    AshRpc.run_action(
      RpcProfile,
      conn,
      %{"action" => action, "input" => %{}, "fields" => ["id"]},
      manifest: manifest
    )
  end

  test "the profile reads both forms from the domain" do
    assert RpcProfile.error_handler(MfaDomain) == {Handler, :handle, ["mfa"]}
    assert RpcProfile.error_handler(ModuleDomain) == Handler
  end

  test "a module that is no Spark DSL module gets the default handler" do
    assert RpcProfile.error_handler(Handler) == {AshRpc.DefaultErrorHandler, :handle_error, []}
  end

  test "an {M, F, A} handler changes the errors of the domain's actions", %{manifest: m} do
    assert %{"success" => false, "errors" => [error]} = run(m, "create_mfa_note")
    assert error["type"] == "required"
    assert error["message"] == "handled by mfa"
  end

  test "a module handler is called as handle_error/2", %{manifest: m} do
    assert %{"success" => false, "errors" => [error]} = run(m, "create_module_note")
    assert error["type"] == "required"
    assert error["message"] == "handled by module"
  end
end
