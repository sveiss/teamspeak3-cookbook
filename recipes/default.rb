#
# Author:: Joshua Timberman <joshua@housepub.org>
# Cookbook Name:: teamspeak3
# Recipe:: default
#
# Copyright 2008-2012, Joshua Timberman
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

arch = node['ts3']['arch']
base = "teamspeak3-server_linux-#{arch}"
basever = "#{base}-#{node['ts3']['version']}"
username = 'teamspeak-server'

service "teamspeak3" do
  action :nothing
end

cached_installation_file = File.join(Chef::Config[:file_cache_path], "#{basever}.tar.gz")

remote_file cached_installation_file do
  source node['ts3']['url']
  mode 0644
  checksum node['ts3']['sha256sum'][arch]

  notifies :create, "ruby_block[validate_ts3_checksum]", :immediately
end

ruby_block "validate_ts3_checksum" do
  action :nothing
  block do
    require 'digest'
    checksum = Digest::SHA256.file(cached_installation_file).hexdigest
    if checksum != node['ts3']['sha256sum'][arch]
      raise "Downloaded TS3 checksum does not match expected value."
    end
  end
end

u = user username do
  action :nothing
  system true
  home "/srv/#{base}"
end

u.run_action(:create)

directory "/srv/#{base}" do
  owner username
  group username
end

execute "install_ts3" do
  cwd "/srv"
  user username
  command "tar zxf #{ cached_installation_file }"
  not_if { ::FileTest.exists?("/srv/#{base}/ts3server_linux_#{arch}") }
end

link "/srv/teamspeak3" do
  to "/srv/#{base}"
end

case node['platform']
when "ubuntu","debian"
  include_recipe "runit" unless node['ts3']['skip_runit_installation']
  runit_service "teamspeak3"
when "arch"
  template "/etc/rc.d/teamspeak3" do
    source "teamspeak3.rc.d.erb"
    owner "root"
    group "root"
    mode 0755
    variables :base => "/srv/#{base}"
  end

  service "teamspeak3" do
    pattern "ts3server_linux_amd64"
    action [:enable, :start]
  end
when "fedora"
  if node[:platform_version].to_i >= 16
    template "/etc/systemd/system/teamspeak3.service" do
      source "teamspeak3.service"
      owner "root"
      group "root"
      mode "0644"
      variables(
        :base => "/srv/#{base}",
        :user => username,
        :group => username
      )
    end

    # distribution ts3server_minimal_runscript.sh almost does the right thhing...
    cookbook_file "/srv/#{base}/ts3server_wrapper" do
      owner username
      group username
      mode "0755"

      source "ts3server_wrapper.sh"
    end

    service "teamspeak3" do
      action [:enable, :start]
    end
  end
end

log "Set up teamspeak3 server. To get the server admin password and token, check the log." do
  action :nothing
  subscribes :write, resources(:execute => "install_ts3")
end
