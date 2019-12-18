defmodule SlackDB.Channels do
  @moduledoc false

  alias SlackDB.Client
  alias SlackDB.Utils

  @callback get_all_convos(String.t()) ::
              {:error, String.t()} | {:ok, list(map())}
  @callback get_all_convos(String.t(), keyword()) ::
              {:error, String.t()} | {:ok, list(map())}
  @callback invite_to_channel(String.t(), String.t() | :supervisor, list(String.t())) ::
              {:error, String.t()} | {:ok, map()}

  defp client(), do: Application.get_env(:slackdb, :client_adapter, Client)

  @spec invite_to_channel(String.t(), String.t() | :supervisor, list(String.t())) ::
          {:error, String.t()} | {:ok, map()}
  def invite_to_channel(server_name, :supervisor, user_ids) when is_list(user_ids) do
    with [supervisor_channel_id] <- Utils.get_tokens(server_name, [:supervisor_channel_id]) do
      invite_to_channel(server_name, supervisor_channel_id, user_ids)
    else
      err -> err
    end
  end

  def invite_to_channel(server_name, channel_id, user_ids) when is_list(user_ids) do
    with [user_token] <- Utils.get_tokens(server_name, [:user_token]) do
      client().conversations_invite(
        user_token,
        channel_id,
        Enum.join(user_ids, ",")
      )
    else
      err -> err
    end
  end

  @doc """
  ## Options
  * `:token_type` - `:bot_token` or `user_token`, default is `user_token`
  """
  @spec get_all_convos(String.t(), keyword()) ::
          {:error, String.t()} | {:ok, list(map())}
  def get_all_convos(server_name, opts \\ []) do
    token_type = Keyword.get(opts, :token_type, :user_token)

    with [token] <- Utils.get_tokens(server_name, [token_type]) do
      paginate_convos(token, nil, [])
    else
      e -> e
    end
  end

  # paginate through conversations.list responeses and collect public+private channels in a list
  # each element of the list is a map containing data about the channel shown at this doc https://api.slack.com/methods/conversations.list
  defp paginate_convos(token, cursor, list) do
    with {:ok, resp} <- client().conversations_list(token, cursor: cursor) do
      case get_in(resp, ["response_metadata", "next_cursor"]) do
        nil -> {:error, "response_parse_error"}
        "" -> {:ok, list ++ resp["channels"]}
        cursor -> paginate_convos(token, cursor, list ++ resp["channels"])
      end
    end
  end
end
