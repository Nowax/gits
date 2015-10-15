#!/usr/bin/env ruby

require 'rubygems'
require 'net/ssh'
require 'optparse'
require 'fileutils'
require 'yaml'
require 'colorize'

class ConfigLoader
  def initialize
    load_config_data
  end

  def for(name)
    @config_data[name] unless @config_data[name].nil?
  end

private

  def load_config_data
    config_file_path = Dir.home + "/.gitsync/config.yml"
    begin
      config_file_contents = File.read(config_file_path)
      @config_data = YAML.load(config_file_contents)
    rescue Errno::ENOENT
      perform_first_configuration config_file_path
      abort
    end
  end

  def perform_first_configuration config_file_path
    new_config_file = create_file config_file_path
    new_config_file.write gather_essential_knowledge.to_yaml
    new_config_file.close
  end

  def create_file path
    dir = File.dirname(path)
    unless File.directory?(dir)
      FileUtils.mkdir_p(dir)
    end
    File.new(path, 'w')
  end

  def gather_essential_knowledge
    puts "I suppose that you're using this script for the first time."
    puts "So maybe you tell me something about yourself..."

    data = {}
    print "What is your username? ".green
    data['username'] = $stdin.gets.chomp
    print "What is your hostname? ".green
    data['hostname'] = $stdin.gets.chomp
    print "What is your git repo's directory on the host? ".green
    data['host_repo_dir'] = $stdin.gets.chomp
    print "What is your git repo's directory on the local machine? ".green
    data['local_repo_dir'] = $stdin.gets.chomp

    puts "You're git commands will be synchronized between your local repo and that one on remote host:"
    puts "#{data['username']}@#{data['hostname']}:#{data['host_repo_dir']}"
    puts "Your local git repo's directory was stored as: #{data['local_repo_dir']}"
    puts "Configuration completed! From now you can use the script correctly.".green

    return data
  end
end

class Gits
  def initialize
    load_configuration
  end

  def main argv
    @arguments = argv
    @debug_lvl = "fatal"
    @supported_commands = ["checkout", "fetch"]

    retrieve_options
    match_command

    unless @command.nil?
      run_command_locally
      run_command_via_ssh
    else
      puts "Command not supported".red
    end
  end

private

  def retrieve_options
    opts = OptionParser.new
    opts.on("-h HOSTNAME", "--hostname HOSTNAME", String, "Hostname of Server") { |v| @hostname = v }
    opts.on("-u SSH USERNAME", "--username SSH USERNAME", String, "SSH Username of Server") { |v| @username = v }
    opts.on("-b BRANCH", "--branch BRANCH", String, "Branch which will be checkouted") { |v| @branch = v }
    opts.on("-d DEBUG", "--debug DEBUG", String, "Debug level for ssh connection (DEBUG=fatal|error|warn|info|debug)") { |v| @debug_lvl = v }
    begin
      opts.parse!(@arguments)
    rescue OptionParser::ParseError => e
      puts e
    end
  end

  def match_command
    @supported_commands.each do |command|
      @command = command if @arguments.include?(command)
    end
  end

  def run_command_via_ssh
    command_info "remotely"
    begin
      ssh = Net::SSH.start(@hostname, @username, :host_key => "ssh-rsa", :verbose => @debug_lvl.to_sym)
      ssh.exec!("cd #{@host_repo_dir} && git #{@command} #{@branch}") do
        |ch, stream, line|
        puts line
      end
      ssh.close
    rescue
      puts "Unable to connect to #{@hostname} using #{@username} username".red
    end
  end

  def run_command_locally
    command_info "locally"
    system("cd #{@local_repo_dir} && git #{@command} #{@branch}");
  end

  def command_info location
    print "Running command: ".green
    print "#{@command}".yellow
    puts " #{location}... ".green
  end

  def load_configuration
    config = ConfigLoader.new
    @hostname = config.for('hostname')
    @username = config.for('username')
    @host_repo_dir = config.for('host_repo_dir')
    @local_repo_dir = config.for('local_repo_dir')
  end
end

###########################################################
################### main program ##########################

Gits.new.main(ARGV)

