#
# Cookbook Name:: maven-deploy
# Recipe:: default
#
# Copyright 2017, YOUR_COMPANY_NAME
#
# All rights reserved - Do Not Redistribute
#
include_recipe 'maven-deploy::forward'

profile = node['maven-deploy']['profile']
source_dir = "#{node['maven-deploy']['dir']}/#{node['maven-deploy']['application']['name']}"
repo = "#{source_dir}/repo"
jar_name = node['maven-deploy']['jar']['name']
jar_location = "#{repo}/#{node['maven-deploy']['jar']['location']}/#{jar_name}"
app_port = node['maven-deploy']['application']['port']
jvm = node['maven-deploy']['jar']['arg']
jvm = "#{jvm} -Dserver.port=#{app_port}"

data_bag_name = node['maven-deploy']['git']['databag']['name']
data_bag_key = node['maven-deploy']['git']['databag']['key']
data_bag_property = node['maven-deploy']['git']['databag']['property']

private_ssh_key = ""

directory source_dir do
  mode '0666'
  action :create
  recursive true
end

directory "/var/log/#{node['maven-deploy']['application']['name']}" do
  mode '0755'
  action :create
  recursive true
end


if node['maven-deploy']['git']['private']
	encrypted_key = Chef::EncryptedDataBagItem.load(data_bag_name, data_bag_key)
	private_ssh_key = encrypted_key[data_bag_property]

	file "/tmp/git_private_key" do
		mode "400"
		sensitive true
		content private_ssh_key
	end

	file "/tmp/git_wrapper.sh" do
	  mode "0755"
	  sensitive true
	  content "#!/bin/sh\nexec /usr/bin/ssh -o \"StrictHostKeyChecking=no\" -i /tmp/git_private_key \"$@\""
	end

	git repo do
	  repository node['maven-deploy']['git']['url']
	  branch node['maven-deploy']['git']['branch']
	  action :sync
	  ssh_wrapper "/tmp/git_wrapper.sh"
	end


	file "/tmp/git_private_key" do
		action :delete
	end
else
	
	file "/tmp/git_wrapper.sh" do
	  mode "0755"
	  content "#!/bin/sh\nexec /usr/bin/ssh -o \"StrictHostKeyChecking=no\" \"$@\""
	end

	git repo do
	  repository node['maven-deploy']['git']['url']
	  branch node['maven-deploy']['git']['branch']
	  action :sync
	  ssh_wrapper "/tmp/git_wrapper.sh"
	end
end

cookbook_file "/tmp/service.sh" do
  source "scripts/service.sh"
  mode 0755
end

bash 'stop current service' do
  code "./tmp/service.sh stop -e #{profile} -jar #{jar_location}"
  only_if { ::File.exist?("/var/run/#{jar_name}.#{profile.downcase}.pid") }
end

bash 'maven build project' do
  code "cd #{repo} && mvn clean install -DskipTests"
end

bash 'start service' do
  code "./tmp/service.sh start -e #{profile} -jar #{jar_location} -arg #{jvm}"
end