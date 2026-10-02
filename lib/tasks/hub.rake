namespace :hub do
  desc "Create or refresh the hub's local CA and HTTPS certificate for this machine's addresses"
  task certs: :environment do
    ca = LocalCa.new.ensure!(hosts: LocalCa.default_hosts, ips: LocalCa.lan_ips + ["127.0.0.1"])
    puts "Root CA:     #{ca.root_cert_path}"
    puts "Server cert: #{ca.server_cert_path}"
  end
end
