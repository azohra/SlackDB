defmodule SlackDB.Channels do
  alias SlackDB.Client

  # paginate through conversations.list responeses and collect public+private channels in a list
  def get_all_convos(
        _user_token,
        array,
        %{"channels" => channels, "response_metadata" => %{"next_cursor" => ""}}
      ) do
    channels ++ array
  end

  def get_all_convos(
        user_token,
        array,
        %{"channels" => channels, "response_metadata" => %{"next_cursor" => cursor}}
      ) do
    with {:ok, next_response} <- Client.conversations_list(user_token, cursor) do
      get_all_convos(
        user_token,
        channels ++ array,
        next_response
      )
    end
  end
end
