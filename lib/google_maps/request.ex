defmodule GoogleMaps.Request do
  @moduledoc false
  require Logger

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

  # TODO: Support other endpoints that require POST requests
  @spec post(String.t, keyword()) :: GoogleMaps.Response.t
  def post(_endpoint, params) do
    Logger.info("[GoogleMaps.Request] POST request initiated")
    Logger.debug("[GoogleMaps.Request] Incoming params: #{inspect(params, pretty: true)}")

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
    url = "https://routes.googleapis.com/distanceMatrix/v2:computeRouteMatrix"

    # Set required headers for JSON and Google API
    headers = [
      {"Content-Type", "application/json"},
      {"X-Goog-Api-Key", key},
      {"X-Goog-FieldMask", "originIndex,destinationIndex,distanceMeters,duration,status,condition"}
      | headers
    ]

    Logger.info("[GoogleMaps.Request] POST URL: #{url}")
    Logger.debug("[GoogleMaps.Request] Request headers: #{inspect(headers, pretty: true)}")
    Logger.info("[GoogleMaps.Request] ===== REQUEST JSON BODY =====")
    Logger.info(body)
    Logger.info("[GoogleMaps.Request] ===== END REQUEST JSON =====")

    response = requester().post(url, body, headers, options)

    # Log the response details
    case response do
      {:ok, %{status_code: status_code, body: response_body} = resp} ->
        Logger.info("[GoogleMaps.Request] Response status: #{status_code}")
        Logger.info("[GoogleMaps.Request] ===== RESPONSE BODY =====")
        Logger.info(response_body)
        Logger.info("[GoogleMaps.Request] ===== END RESPONSE =====")
        Logger.debug("[GoogleMaps.Request] Full response struct: #{inspect(resp, pretty: true)}")

      {:error, error} ->
        Logger.error("[GoogleMaps.Request] Request failed with error: #{inspect(error, pretty: true)}")

      _ ->
        Logger.debug("[GoogleMaps.Request] Response: #{inspect(response, pretty: true)}")
    end

    # IO.inspect(response, label: "POST Response")
    format_headers(response)
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
    Logger.debug("[GoogleMaps.Request] Starting transform_post_params with: #{inspect(params, pretty: true)}")

    result = params
    |> Enum.into(%{})
    |> transform_origins()
    |> transform_destinations()
    |> clean_invalid_params()

    Logger.debug("[GoogleMaps.Request] After transformation: #{inspect(result, pretty: true)}")
    result
  end

  # Remove parameters that are not valid for Routes API v2
  defp clean_invalid_params(params) do
    # The 'avoid' parameter is not a top-level parameter in Routes API v2
    # It's already handled in routeModifiers for origins
    params
    |> Map.delete(:avoid)
  end

  defp transform_origins(%{origins: origins} = params) when is_list(origins) do
    Logger.debug("[GoogleMaps.Request] Transforming origins list: #{inspect(origins)}")

    transformed_origins =
      origins
      |> Enum.map(&transform_waypoint/1)
      |> Enum.map(&add_route_modifiers/1)

    Logger.debug("[GoogleMaps.Request] Transformed origins: #{inspect(transformed_origins, pretty: true)}")
    %{params | origins: transformed_origins}
  end
  defp transform_origins(params), do: params

  defp transform_destinations(%{destinations: destinations} = params) when is_list(destinations) do
    Logger.debug("[GoogleMaps.Request] Transforming destinations list: #{inspect(destinations)}")

    transformed_destinations = Enum.map(destinations, &transform_waypoint/1)

    Logger.debug("[GoogleMaps.Request] Transformed destinations: #{inspect(transformed_destinations, pretty: true)}")
    %{params | destinations: transformed_destinations}
  end
  defp transform_destinations(params), do: params

  # Add route modifiers only to origin waypoints
  defp add_route_modifiers(waypoint) do
    Map.put(waypoint, :routeModifiers, %{
      avoidFerries: true
    })
  end

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

  # Handle encoded polylines (e.g., "enc:...")
  defp transform_waypoint("enc:" <> encoded_polyline) do
    # Strip trailing colon if present
    cleaned_polyline = String.trim_trailing(encoded_polyline, ":")
    Logger.debug("[GoogleMaps.Request] Transforming encoded polyline (cleaned): enc:#{String.slice(cleaned_polyline, 0, 50)}...")
    %{
      waypoint: %{
        via: false,
        polyline: %{
          encodedPolyline: cleaned_polyline
        }
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
