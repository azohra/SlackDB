defmodule SlackDB.Channels do
  @moduledoc false

  alias SlackDB.Client

  @callback get_all_convos(String.t()) :: list(map())

  def get_all_convos(user_token) do
    with {:ok, resp} <- Client.conversations_list(user_token) do
      paginate_convos(user_token, [], resp)
    else
      err -> err
    end
  end

  # paginate through conversations.list responeses and collect public+private channels in a list
  # each element of the list is a map containing data about the channel shown at this doc https://api.slack.com/methods/conversations.list
  defp paginate_convos(
         _user_token,
         array,
         %{"channels" => channels, "response_metadata" => %{"next_cursor" => ""}}
       ) do
    channels ++ array
  end

  defp paginate_convos(
         user_token,
         array,
         %{"channels" => channels, "response_metadata" => %{"next_cursor" => cursor}}
       ) do
    with {:ok, next_response} <- Client.conversations_list(user_token, cursor) do
      paginate_convos(
        user_token,
        channels ++ array,
        next_response
      )
    end
  end
end
