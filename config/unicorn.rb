root = "/home/deployer/apps/data-warehouse/current"
working_directory root
pid "#{root}/tmp/pids/unicorn.pid"
stderr_path "#{root}/log/unicorn.log"
stdout_path "#{root}/log/unicorn.log"

listen "/tmp/unicorn.dssdw.sock"
worker_processes 5
timeout 30
