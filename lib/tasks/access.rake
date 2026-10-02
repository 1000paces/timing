namespace :access do
  desc "Create the first admin official: NAME=... [PIN=...] (prints a random PIN if none given)"
  task bootstrap: :environment do
    abort "Officials already exist; sign in as an admin to add more." if Official.exists?
    pin = ENV["PIN"].presence || format("%06d", SecureRandom.random_number(1_000_000))
    official = Official.create!(name: ENV.fetch("NAME", "Admin"), role: "admin", pin:)
    puts "Created admin #{official.name} with PIN #{pin}"
  end
end
