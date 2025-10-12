# SPDX-FileCopyrightText: 2025 Torkild G. Kjevik
#
# SPDX-License-Identifier: MIT

defmodule AshTypescript.Rpc.Info do
  @moduledoc """
  Provides introspection functions for AshTypescript.Rpc configuration.

  This module generates helper functions to access RPC configuration
  defined in domains using the AshTypescript.Rpc DSL extension.
  """
  use Spark.InfoGenerator, extension: AshTypescript.Rpc, sections: [:typescript_rpc]
end
