namespace :console do
  desc "Install frontend dependencies and build the ops console into public/console"
  task :build do
    Dir.chdir(Rails.root.join("frontend")) { sh "npm ci && npm run build" }
  end
end
