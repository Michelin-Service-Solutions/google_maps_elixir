defmodule GoogleMaps.Request do
  @moduledoc false

  @doc """
  GET an endpoint with param keyword list
  """
  @spec get(String.t, keyword()) :: GoogleMaps.Response.t
  def get(endpoint, params) do
    {secure, params} = Keyword.pop(params, :secure)
    {output, params} = Keyword.pop(params, :output, "json")
    {key, params} = Keyword.pop(params, :key, api_key())
    {headers, params} = Keyword.pop(params, :headers, [])
    {options, params} = Keyword.pop(params, :options, [])

    unless is_nil(secure) do
      IO.puts "`secure` param is deprecated since Google requires request over SSL with API key."
    end

    query = params
      |> Keyword.put(:key, key)
      |> Enum.map(&transform_param/1)
      |> URI.encode_query()

    url = Path.join("https://maps.googleapis.com/maps/api/#{endpoint}", output)

    requester().get("#{url}?#{query}", headers, options)
    |> format_headers()
  end


  @spec post(String.t, keyword()) :: GoogleMaps.Response.t
  def post(_endpoint, params) do
    {secure, params} = Keyword.pop(params, :secure)
    {key, params} = Keyword.pop(params, :key, api_key())
    {headers, params} = Keyword.pop(params, :headers, [])
    {options, params} = Keyword.pop(params, :options, [])

    unless is_nil(secure) do
      IO.puts "`secure` param is deprecated since Google requires request over SSL with API key."
    end

    # Build JSON body from remaining params
    body = params
      |> transform_post_params()
      |> json_encode()

    # Add API key to URL as query parameter
    url = "https://routes.googleapis.com/distanceMatrix/v2:computeRouteMatrix?key=#{key}"

    # Set required headers for JSON and Google API
    headers = [
      {"Content-Type", "application/json"},
      {"x-goog-api-key", key},
      {"x-goog-fieldmask", "originIndex,distanceMeters,duration,staticDuration"}
      | headers
    ]

    requester().post(url, headers, [body: body] ++ options)
    |> format_headers()
  end

  # Helpers

  defp api_key do
    Application.get_env(:google_maps, :api_key) ||
      System.get_env("GOOGLE_MAPS_API_KEY")
  end

  defp requester do
    Application.get_env(:google_maps, :requester)
  end

  defp json_encode(data) do
    Jason.encode!(data)
  end

  # Transform params for POST request JSON body
  defp transform_post_params(params) do
    params
    |> Enum.into(%{})
    |> transform_origins()
    |> transform_destinations()
  end

  defp transform_origins(%{origins: origins} = params) when is_list(origins) do
    transformed_origins = Enum.map(origins, &transform_waypoint/1)
    %{params | origins: transformed_origins}
  end
  defp transform_origins(params), do: params

  defp transform_destinations(%{destinations: destinations} = params) when is_list(destinations) do
    transformed_destinations = Enum.map(destinations, &transform_waypoint/1)
    %{params | destinations: transformed_destinations}
  end
  defp transform_destinations(params), do: params

  defp transform_waypoint({lat, lng}) when is_number(lat) and is_number(lng) do
    %{
      waypoint: %{
        location: %{
          latLng: %{
            latitude: lat,
            longitude: lng
          }
        }
      }
    }
  end

  defp transform_waypoint({:place_id, place_id}) do
    %{
      waypoint: %{
        placeId: place_id
      }
    }
  end

  defp transform_waypoint(address) when is_binary(address) do
    %{
      waypoint: %{
        address: address
      }
    }
  end

  defp transform_waypoint(waypoint) when is_map(waypoint), do: waypoint

  defp transform_param({type, {lat, lng}})
  when type in [:origin, :destination]
  and is_number(lat)
  and is_number(lng)
  do
    {type, "#{lat},#{lng}"}
  end

  defp transform_param({type, {:place_id, place_id}})
  when type in [:origin, :destination]
  do
    {type, "place_id:#{place_id}"}
  end

  defp transform_param({:waypoints, "enc:" <> enc}) do
    {:waypoints, "enc:" <> enc}
  end

  defp transform_param({:waypoints, waypoints})
  when is_list(waypoints) do
    transform_param({:waypoints, Enum.join(waypoints, "|")})
  end

  defp transform_param({:waypoints, waypoints}) do
    # @TODO: Encode the waypoints into encoded polyline.
    {:waypoints, "optimize:true|#{waypoints}"}
  end

  defp transform_param(param), do: param

  defp format_headers({:ok, %{headers: headers} = response}) do
    {:ok, %{response | headers: Map.new(headers)}}
  end

  defp format_headers(error), do: error
end
