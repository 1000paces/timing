require "test_helper"

class LocalCaTest < ActiveSupport::TestCase
  setup do
    @dir = Dir.mktmpdir
    @ca = LocalCa.new(@dir)
  end

  teardown { FileUtils.remove_entry(@dir) }

  test "default_hosts covers the machine hostname, its .local name and localhost" do
    hosts = LocalCa.default_hosts
    assert_includes hosts, "#{Socket.gethostname.split('.').first}.local"
    assert_includes hosts, "localhost"
  end

  def verify(cert_path)
    store = OpenSSL::X509::Store.new
    store.add_cert(OpenSSL::X509::Certificate.new(File.read(@ca.root_cert_path)))
    store.verify(OpenSSL::X509::Certificate.new(File.read(cert_path)))
  end

  def san(path)
    cert = OpenSSL::X509::Certificate.new(File.read(path))
    cert.extensions.find { it.oid == "subjectAltName" }.value
  end

  test "creates a root CA and a server certificate it signs, with hosts and IPs" do
    @ca.ensure!(hosts: ["hub.local", "localhost"], ips: ["192.168.1.20", "127.0.0.1"])
    assert verify(@ca.server_cert_path)
    assert_includes san(@ca.server_cert_path), "IP Address:192.168.1.20"
    assert_includes san(@ca.server_cert_path), "DNS:hub.local"
    server = OpenSSL::X509::Certificate.new(File.read(@ca.server_cert_path))
    assert_operator server.not_after, :<=, Time.now + 397 * 86_400
    assert_equal "600", format("%o", File.stat(@ca.server_key_path).mode & 0o777)
    assert_equal "600", format("%o", File.stat(@ca.root_key_path).mode & 0o777)
    assert_equal "700", format("%o", File.stat(@dir).mode & 0o777)
  end

  test "repairs loose permissions on existing keys" do
    @ca.ensure!(hosts: ["hub.local"], ips: ["192.168.1.20"])
    File.chmod(0o644, @ca.root_key_path)
    @ca.ensure!(hosts: ["hub.local"], ips: ["192.168.1.20"])
    assert_equal "600", format("%o", File.stat(@ca.root_key_path).mode & 0o777)
  end

  test "reissues when the server key does not match the certificate" do
    @ca.ensure!(hosts: ["hub.local"], ips: ["192.168.1.20"])
    File.write(@ca.server_key_path, OpenSSL::PKey::RSA.new(2048).to_pem)
    @ca.ensure!(hosts: ["hub.local"], ips: ["192.168.1.20"])
    cert = OpenSSL::X509::Certificate.new(File.read(@ca.server_cert_path))
    assert cert.check_private_key(OpenSSL::PKey::RSA.new(File.read(@ca.server_key_path)))
  end

  test "root fingerprint is colon-separated uppercase SHA-256 hex" do
    @ca.ensure!(hosts: ["hub.local"], ips: ["192.168.1.20"])
    assert_match(/\A([0-9A-F]{2}:){31}[0-9A-F]{2}\z/, @ca.root_fingerprint)
  end

  test "keeps a current certificate, reissues when the network address changes" do
    @ca.ensure!(hosts: ["hub.local"], ips: ["192.168.1.20"])
    root = File.read(@ca.root_cert_path)
    first = File.read(@ca.server_cert_path)
    @ca.ensure!(hosts: ["hub.local"], ips: ["192.168.1.20"])
    assert_equal first, File.read(@ca.server_cert_path)
    @ca.ensure!(hosts: ["hub.local"], ips: ["10.0.0.5"])
    refute_equal first, File.read(@ca.server_cert_path)
    assert_equal root, File.read(@ca.root_cert_path)
    assert verify(@ca.server_cert_path)
  end
end
