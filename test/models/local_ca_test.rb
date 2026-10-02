require "test_helper"

class LocalCaTest < ActiveSupport::TestCase
  setup do
    @dir = Dir.mktmpdir
    @ca = LocalCa.new(@dir)
  end

  teardown { FileUtils.remove_entry(@dir) }

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
