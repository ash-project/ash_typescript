# SPDX-FileCopyrightText: 2025 ash_typescript contributors <https://github.com/ash-project/ash_typescript/graphs/contributors>
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Test.SecondDomain do
  @moduledoc """
  Second test domain for testing duplicate resource schema generation.

  This domain exposes the User resource to test that we don't generate
  duplicate resource schemas when the same resource is exposed in multiple domains.
  """
  use Ash.Domain,
    otp_app: :ash_typescript,
    extensions: [AshTypescript.Rpc]

  typescript_rpc do
    resource AshTypescript.Test.User do
      rpc_action :list_users_second, :read
      rpc_action :get_user_by_id_second, :get_by_id

      typed_query :list_users_second_domain, :read do
        ts_fields_const_name "listUsersSecondDomain"
        ts_result_type_name "ListUsersSecondDomainResult"
        fields [:id, :name, :email, :address_line_1, :is_active?]
      end
    end
  end

  resources do
    resource AshTypescript.Test.User
  end
end
