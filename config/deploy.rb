require "bundler/capistrano"

# 'whenever' setup
set :whenever_command, "bundle exec whenever"
require "whenever/capistrano"

after "deploy:restart", "deploy:prime_cache"

server "169.237.120.176", :web, :app, :db, primary: true

set :application, "data-warehouse"
set :url, "https://dw.dss.ucdavis.edu/"
set :user, "deployer"
set :deploy_to, "/home/#{user}/apps/#{application}"
set :deploy_via, :remote_cache
set :use_sudo, false

set :scm, "git"
set :repository, "git@github.com:cthielen/#{application}.git"
set :branch, "master"

set :test_log, "log/capistrano.test.log"

default_run_options[:pty] = true
ssh_options[:forward_agent] = true

after "deploy", "deploy:cleanup" # keep only the last 5 releases
after "deploy", "deploy:migrations" # run any pending migrations

namespace :deploy do
  before 'deploy:update_code' do
    puts "--> Running tests, please wait ..."
    unless system "bundle exec rake > #{test_log} 2>&1" #' > /dev/null'
      puts "--> Tests failed. Run `cat #{test_log}` to see what went wrong."
      exit
    else
      puts "--> Tests passed"
      system "rm #{test_log}"
    end
  end

  %w[start stop restart].each do |command|
    desc "#{command} unicorn server"
    task command, roles: :app, except: {no_release: true} do
      run "/etc/init.d/unicorn_#{application} #{command}"
    end
  end

  task :setup_config, roles: :app do
    sudo "ln -nfs #{current_path}/config/nginx.conf /etc/nginx/sites-enabled/#{application}"
    sudo "ln -nfs #{current_path}/config/unicorn_init.sh /etc/init.d/unicorn_#{application}"
    run "mkdir -p #{shared_path}/config"
    put File.read("config/database.example.yml"), "#{shared_path}/config/database.yml"
    put File.read("config/banner.example.yml"), "#{shared_path}/config/banner.yml"
    puts "Now edit the config files in #{shared_path}."
  end
  after "deploy:setup", "deploy:setup_config"

  task :symlink_config, roles: :app do
    run "ln -nfs #{shared_path}/config/database.yml #{release_path}/config/database.yml"
    run "ln -nfs #{shared_path}/config/banner.yml #{release_path}/config/banner.yml"
    run "ln -nfs #{shared_path}/config/iam.yml #{release_path}/config/iam.yml"
  end
  after "deploy:finalize_update", "deploy:symlink_config"

  desc "Make sure local git is in sync with remote."
  task :check_revision, roles: :web do
    unless `git rev-parse HEAD` == `git rev-parse origin/master`
      puts "WARNING: HEAD is not the same as origin/master"
      puts "Run `git push` to sync changes."
      exit
    end
  end
  before "deploy", "deploy:check_revision"

  desc "Prime cache using curl"
    task :prime_cache, roles: :web do
      run "curl #{url} >/dev/null 2>&1; true"
    end
end
