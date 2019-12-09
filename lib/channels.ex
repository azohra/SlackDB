defmodule SlackDB.Channels do
  @moduledoc false

  alias SlackDB.Client

  @callback get_all_convos(String.t(), :bot_token | :user_token) ::
              {:error, any()} | {:ok, list(map())}

  defp client(), do: Application.get_env(:slackdb, :client_adapter, Client)

  def get_all_convos(server_name, token_type \\ :user_token) do
    with token when is_binary(token) <-
           Application.get_env(:slackdb, :servers) |> get_in([server_name, token_type]) do
      paginate_convos(token, nil, [])
    else
      _err -> {:error, "improper_config"}
    end
  end

  # paginate through conversations.list responeses and collect public+private channels in a list
  # each element of the list is a map containing data about the channel shown at this doc https://api.slack.com/methods/conversations.list
  defp paginate_convos(token, cursor, list) do
    with {:ok, resp} <- client().conversations_list(token, cursor) |> IO.inspect() do
      case get_in(resp, ["response_metadata", "next_cursor"]) do
        nil -> {:error, "response_parse_error"}
        "" -> {:ok, list ++ resp["channels"]}
        cursor -> paginate_convos(token, cursor, list ++ resp["channels"])
      end
    end
  end
end
