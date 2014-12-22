#
# Cookbook Name:: scala-jenkins-infra
# Recipe:: master
#
# Copyright 2014, Typesafe, Inc.
#
# All rights reserved - Do Not Redistribute
#
chef_gem "chef-vault"
require "chef-vault"


# The jenkins cookbook comes with a very simple java installer. If you need more
#  complex java installs you are on your own.
#  https://github.com/opscode-cookbooks/jenkins#java
include_recipe 'jenkins::java'
include_recipe 'jenkins::master'

directory "#{node['jenkins']['master']['home']}/users/chef/" do
  user node['jenkins']['master']['user']
  group node['jenkins']['master']['group']
  recursive true
end

# set up chef user with public key from our master/scala-jenkins-keypair vault
template "#{node['jenkins']['master']['home']}/users/chef/config.xml" do
  source 'chef-user-config.erb'
  user node['jenkins']['master']['user']
  group node['jenkins']['master']['group']

  variables({
    :pubkey => ChefVault::Item.load("master", "scala-jenkins-keypair")['public_key']
  })
end

ruby_block 'set private key' do
  block do
    node.run_state[:jenkins_private_key] = ChefVault::Item.load("master", "scala-jenkins-keypair")['private_key']
  end
end

%w(ssh-credentials github-oauth job-dsl greenballs build-timeout copyartifact email-ext slack throttle-concurrents dashboard-view parameterized-trigger).each do |plugin|
  plugin, version = plugin.split('=') # in case we decide to pin versions later
  jenkins_plugin plugin
end

# If auth scheme is set, include recipe with that implementation.
if node['master']['auth']
  include_recipe "scala-jenkins-infra::_auth-#{node['master']['auth']}"
end

jenkins_private_key_credentials 'jenkins' do # username == name of resource
  id '954dd564-ce8c-43d1-bcc5-97abffc81c54'
  private_key ChefVault::Item.load("master", "scala-jenkins-keypair")['private_key']
end

search(:node, 'name:jenkins-worker* AND os:linux').each do |worker|
  jenkins_ssh_slave 'builder-publish' do
    host    worker.ipaddress
    credentials '954dd564-ce8c-43d1-bcc5-97abffc81c54' # must use id (groovy script fails otherwise)

    # TODO filter tags that don't start with "jenkins-worker-"
    labels worker.tags.map{|t| t.tap{|s| s.slice!("jenkins-worker-"); s}} + ["linux"]

    executors 2

    environment(worker["worker"]["env"])

    action [:create, :connect]
  end
end