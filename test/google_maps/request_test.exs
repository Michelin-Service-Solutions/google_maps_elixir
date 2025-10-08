defmodule GoogleMaps.RequestTest do
  use ExUnit.Case, async: false
  alias GoogleMaps.Request, as: Request
  import ExUnit.CaptureIO

  defmodule MockRequest do
    def get(url, headers, options) do
      {:ok, %{body: url, headers: headers, options: options}}
    end

    def post(url, headers, options) do
      {:ok, %{body: url, headers: headers, options: options}}
    end
  end

  setup do
    requester = Application.get_env(:google_maps, :requester)
    Application.put_env(:google_maps, :requester, MockRequest)

    on_exit fn ->
      Application.put_env(:google_maps, :requester, requester)
    end

    :ok
  end

  test "construct full URL from endpoint" do
    {:ok, %{body: url}} = Request.get("foobar", [])
    assert %{
      scheme: "https",
      authority: "maps.googleapis.com",
      path: "/maps/api/foobar/json"
    } = URI.parse(url)
  end

  test "convert params to query" do
    params = [key: "key", foo: "param1", bar: "param2"]
    {:ok, %{body: url}} = Request.get("foobar", params)
    assert %{query: "key=key&foo=param1&bar=param2"} = URI.parse(url)
  end

  test "supports headers" do
    params = [headers: %{"Accept-Language" => "vi"}]
    {:ok, %{headers: headers}} = Request.get("foobar", params)
    assert headers === params[:headers]
  end

  test "supports options" do
    params = [options: [proxy: "localhost"]]
    {:ok, %{options: options}} = Request.get("foobar", params)
    assert options === params[:options]
  end

  test "deprecates `secure` param and still requests over SSL" do
    params = [secure: false, key: "key", param: "param"]
    {:ok, %{body: url}} = Request.get("foobar", params)
    assert %{
      scheme: "https",
      authority: "maps.googleapis.com",
      path: "/maps/api/foobar/json",
      query: "key=key&param=param"
    } = URI.parse(url)

    assert capture_io(fn ->
      Request.get("foobar", params)
    end) =~ "`secure` param is deprecated"
  end

  # POST function tests
  test "POST constructs correct URL with API key" do
    params = [key: "test_api_key", origins: [{34.9489252, -82.2282223}]]
    {:ok, %{body: url}} = Request.post("distance_matrix", params)

    assert %{
      scheme: "https",
      authority: "routes.googleapis.com",
      path: "/distanceMatrix/v2:computeRouteMatrix",
      query: "key=test_api_key"
    } = URI.parse(url)
  end

  test "POST sets correct Content-Type header" do
    params = [origins: [{34.9489252, -82.2282223}]]
    {:ok, %{headers: headers}} = Request.post("distance_matrix", params)

    assert {"Content-Type", "application/json"} in headers
  end

  test "POST sets required Google API headers" do
    params = [key: "test_api_key", origins: [{34.9489252, -82.2282223}]]
    {:ok, %{headers: headers}} = Request.post("distance_matrix", params)

    assert {"Content-Type", "application/json"} in headers
    assert {"x-goog-api-key", "test_api_key"} in headers
    assert {"x-goog-fieldmask", "originIndex,distanceMeters,duration,staticDuration"} in headers
  end

  test "POST transforms coordinate origins correctly" do
    params = [origins: [{34.9489252, -82.2282223}]]
    {:ok, %{options: options}} = Request.post("distance_matrix", params)

    # Extract the body from options
    body = Keyword.get(options, :body)
    parsed_body = Jason.decode!(body)

    assert [%{
      "waypoint" => %{
        "location" => %{
          "latLng" => %{
            "latitude" => 34.9489252,
            "longitude" => -82.2282223
          }
        }
      },
      "routeModifiers" => %{
        "avoidFerries" => true
      }
    }] = parsed_body["origins"]
  end

  test "POST transforms address destinations correctly" do
    params = [destinations: ["1 The Parkway, Greenville, SC 29615, USA"]]
    {:ok, %{options: options}} = Request.post("distance_matrix", params)

    body = Keyword.get(options, :body)
    parsed_body = Jason.decode!(body)

    assert [%{
      "waypoint" => %{
        "address" => "1 The Parkway, Greenville, SC 29615, USA"
      }
    }] = parsed_body["destinations"]
  end

  test "POST transforms place_id destinations correctly" do
    params = [destinations: [{:place_id, "ChIJExample123"}]]
    {:ok, %{options: options}} = Request.post("distance_matrix", params)

    body = Keyword.get(options, :body)
    parsed_body = Jason.decode!(body)

    assert [%{
      "waypoint" => %{
        "placeId" => "ChIJExample123"
      }
    }] = parsed_body["destinations"]
  end

  test "POST includes other parameters in JSON body" do
    params = [
      origins: [{34.9489252, -82.2282223}],
      destinations: ["1 The Parkway, Greenville, SC 29615, USA"],
      travelMode: "DRIVE",
      routingPreference: "TRAFFIC_AWARE"
    ]
    {:ok, %{options: options}} = Request.post("distance_matrix", params)

    body = Keyword.get(options, :body)
    parsed_body = Jason.decode!(body)

    assert parsed_body["travelMode"] == "DRIVE"
    assert parsed_body["routingPreference"] == "TRAFFIC_AWARE"
  end

  test "POST supports custom headers" do
    params = [
      key: "custom_key",
      origins: [{34.9489252, -82.2282223}],
      headers: [{"Authorization", "Bearer token123"}]
    ]
    {:ok, %{headers: headers}} = Request.post("distance_matrix", params)

    assert {"Content-Type", "application/json"} in headers
    assert {"x-goog-api-key", "custom_key"} in headers
    assert {"x-goog-fieldmask", "originIndex,distanceMeters,duration,staticDuration"} in headers
    assert {"Authorization", "Bearer token123"} in headers
  end

  test "POST deprecates `secure` param" do
    params = [secure: false, origins: [{34.9489252, -82.2282223}]]

    assert capture_io(fn ->
      Request.post("distance_matrix", params)
    end) =~ "`secure` param is deprecated"
  end
end
