namespace :hub do
  desc "Create or refresh the hub's local CA and HTTPS certificate for this machine's addresses"
  task certs: :environment do
    ca = LocalCa.new.ensure!(hosts: LocalCa.default_hosts, ips: LocalCa.lan_ips + ["127.0.0.1"])
    puts "Root CA:     #{ca.root_cert_path}"
    puts "Server cert: #{ca.server_cert_path}"
    puts "Root fingerprint (SHA-256): #{ca.root_fingerprint}"
  end

  desc "Create a demo CX event (prints its id)"
  task demo: :environment do
    event = RaceSimulator::Demo.create!
    puts "Demo event #{event.id}. Race it: bin/simulate-race --event #{event.id}"
  end

  desc "Print standings in the terminal: EVENT=<id> [WATCH=1 to refresh every 2 s]"
  task standings: :environment do
    event = Event.find(ENV.fetch("EVENT") { abort "Set EVENT=<event id>" })
    loop do
      print "\e[H\e[2J" if ENV["WATCH"]
      puts RaceSimulator::Table.render(StandingsService.report(event))
      break unless ENV["WATCH"]
      sleep 2
    end
  end
end
