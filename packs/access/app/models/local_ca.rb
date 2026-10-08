require "openssl"

# The hub's own certificate authority (spec §8, option A): crew tablets trust the
# root once; the hub issues itself a server certificate for its LAN addresses.
class LocalCa
  ROOT_DAYS = 3650
  SERVER_DAYS = 397 # Apple's limit for TLS server certificates
  RENEW_WITHIN_DAYS = 30
  DAY = 86_400

  def self.lan_ips = Socket.ip_address_list.select { it.ipv4? && !it.ipv4_loopback? }.map(&:ip_address)

  def self.default_hosts
    host = Socket.gethostname
    [ host, "#{host.split('.').first}.local", "localhost" ].uniq
  end

  def initialize(dir = Rails.root.join("storage/certs"))
    @dir = Pathname(dir)
  end

  def root_cert_path = @dir.join("root-ca.crt")
  def root_key_path = @dir.join("root-ca.key")
  def server_cert_path = @dir.join("server.crt")
  def server_key_path = @dir.join("server.key")

  def ensure!(hosts:, ips:)
    FileUtils.mkdir_p(@dir)
    File.chmod(0o700, @dir)
    [ root_key_path, server_key_path ].each { File.chmod(0o600, it) if it.exist? }
    ensure_root!
    ensure_server!(hosts.uniq, ips.uniq)
    self
  end

  def root_fingerprint
    OpenSSL::Digest::SHA256.hexdigest(OpenSSL::X509::Certificate.new(root_cert_path.read).to_der)
                           .upcase.scan(/../).join(":")
  end

  private

  def ensure_root!
    return if root_cert_path.exist? && root_key_path.exist?
    key = OpenSSL::PKey::RSA.new(2048)
    cert = build(subject: "/CN=Timing Hub Local CA #{SecureRandom.hex(4)}", key:, issuer: nil, issuer_key: key, days: ROOT_DAYS) do |c, ef|
      c.add_extension ef.create_extension("basicConstraints", "CA:TRUE", true)
      c.add_extension ef.create_extension("keyUsage", "keyCertSign,cRLSign", true)
      c.add_extension ef.create_extension("subjectKeyIdentifier", "hash", false)
    end
    write(root_key_path, key.to_pem, 0o600)
    write(root_cert_path, cert.to_pem, 0o644)
  end

  def ensure_server!(hosts, ips)
    root = OpenSSL::X509::Certificate.new(root_cert_path.read)
    return if current?(root, hosts, ips)
    key = OpenSSL::PKey::RSA.new(2048)
    alt_names = (hosts.map { "DNS:#{it}" } + ips.map { "IP:#{it}" }).join(",")
    cert = build(subject: "/CN=#{hosts.first || 'timing-hub'}", key:, issuer: root,
                 issuer_key: OpenSSL::PKey::RSA.new(root_key_path.read), days: SERVER_DAYS) do |c, ef|
      c.add_extension ef.create_extension("basicConstraints", "CA:FALSE", true)
      c.add_extension ef.create_extension("keyUsage", "digitalSignature,keyEncipherment", true)
      c.add_extension ef.create_extension("extendedKeyUsage", "serverAuth", false)
      c.add_extension ef.create_extension("subjectAltName", alt_names, false)
    end
    write(server_key_path, key.to_pem, 0o600)
    write(server_cert_path, cert.to_pem, 0o644)
  end

  def current?(root, hosts, ips)
    return false unless server_cert_path.exist? && server_key_path.exist?
    cert = OpenSSL::X509::Certificate.new(server_cert_path.read)
    return false if cert.issuer.to_s != root.subject.to_s
    return false unless cert.check_private_key(OpenSSL::PKey::RSA.new(server_key_path.read))
    return false if cert.not_after < Time.now + RENEW_WITHIN_DAYS * DAY
    alt = cert.extensions.find { it.oid == "subjectAltName" }&.value.to_s.split(", ").sort
    alt == (hosts.map { "DNS:#{it}" } + ips.map { "IP Address:#{it}" }).sort
  end

  def build(subject:, key:, issuer:, issuer_key:, days:)
    cert = OpenSSL::X509::Certificate.new
    cert.version = 2
    cert.serial = OpenSSL::BN.rand(64)
    cert.subject = OpenSSL::X509::Name.parse(subject)
    cert.issuer = issuer ? issuer.subject : cert.subject
    cert.public_key = key
    cert.not_before = Time.now - 60
    cert.not_after = Time.now + days * DAY
    ef = OpenSSL::X509::ExtensionFactory.new
    ef.subject_certificate = cert
    ef.issuer_certificate = issuer || cert
    yield cert, ef
    cert.add_extension ef.create_extension("authorityKeyIdentifier", "keyid:always", false) if issuer
    cert.sign(issuer_key, OpenSSL::Digest.new("SHA256"))
    cert
  end

  def write(path, contents, mode)
    File.write(path, contents, perm: mode)
    File.chmod(mode, path)
  end
end
