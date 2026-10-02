require "test_helper"

class OnboardingTest < ActionDispatch::IntegrationTest
  setup do
    @dir = Dir.mktmpdir
    @ca = LocalCa.new(@dir)
    @ca.ensure!(hosts: ["localhost"], ips: ["127.0.0.1"])
    OnboardingController.local_ca = @ca
  end

  teardown do
    OnboardingController.local_ca = nil
    FileUtils.remove_entry(@dir)
  end

  test "onboarding page explains setup and links the CA certificate" do
    get "/onboarding"
    assert_response :ok
    assert_includes response.body, "/onboarding/ca.crt"
    assert_includes response.body, "https://"
    assert_includes response.body, @ca.root_fingerprint
  end

  test "CA certificate is a 404 when none exists" do
    Dir.mktmpdir do |empty|
      OnboardingController.local_ca = LocalCa.new(empty)
      get "/onboarding/ca.crt"
      assert_response :not_found
    end
  end

  test "CA certificate downloads" do
    get "/onboarding/ca.crt"
    assert_response :ok
    assert_equal "application/x-x509-ca-cert", response.media_type
    assert_equal File.read(@ca.root_cert_path), response.body
  end
end
