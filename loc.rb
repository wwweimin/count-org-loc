# frozen_string_literal: true

require 'octokit'
require 'open3'
require 'cliver'
require 'fileutils'
require 'dotenv'

if ARGV.count != 1
  puts 'Usage: script/count [ORG NAME]'
  exit 1
end

Dotenv.load

# Load the personal access token from environment variables
access_token = ENV['ORG_PERSONAL_ACCESS_TOKEN'] || ENV['GITHUB_TOKEN']
unless access_token
  puts 'Error: Personal access token is not set. Please set ORG_PERSONAL_ACCESS_TOKEN in your secrets.'
  exit 1
end

# Define cloc method to use Cloc for counting lines of code
def cloc(*args)
  cloc_path = Cliver.detect! 'cloc'
  Open3.capture2e(cloc_path, *args)
end

# Create a temporary directory for cloning repositories
tmp_dir = File.expand_path './tmp', File.dirname(__FILE__)
FileUtils.rm_rf tmp_dir
FileUtils.mkdir_p tmp_dir

# Configure Octokit for GitHub Enterprise support if applicable
unless ENV['GITHUB_ENTERPRISE_URL'].nil?
  Octokit.configure do |c|
    c.api_endpoint = ENV['GITHUB_ENTERPRISE_URL']
  end
end

# Initialize Octokit client
client = Octokit::Client.new access_token: access_token
client.auto_paginate = true

# Fetch organization repositories
begin
  repos = client.organization_repositories(ARGV[0].strip, type: 'sources')
rescue Octokit::NotFound
  puts "Error: Organization #{ARGV[0]} not found or token lacks access."
  exit 1
rescue Octokit::Unauthorized
  puts 'Error: Unauthorized. Please check your access token.'
  exit 1
rescue StandardError => e
  puts "Error: #{e.message}"
  exit 1
end

puts "Found #{repos.count} repos. Counting lines of code..."

# Iterate through repositories and count lines of code
reports = []
repos.each do |repo|
  puts "Counting #{repo.name}..."

  destination = File.expand_path repo.name, tmp_dir
  report_file = File.expand_path "#{repo.name}.txt", tmp_dir

  clone_url = repo.clone_url
  clone_url = clone_url.sub('//', "//#{access_token}:x-oauth-basic@") if access_token
  _output, status = Open3.capture2e 'git', 'clone', '--depth', '1', '--quiet', clone_url, destination
  next unless status.exitstatus.zero?

  _output, _status = cloc destination, '--quiet', "--report-file=#{report_file}"
  reports.push(report_file) if File.exist?(report_file) && _status.exitstatus.zero?
end

# Summing up results from all reports
puts 'Done. Summing up lines of code...'

output, _status = cloc '--sum-reports', *reports
puts output.gsub(%r{^#{Regexp.escape tmp_dir}/(.*)\.txt}) { Regexp.last_match(1) + ' ' * (tmp_dir.length + 5) }

# Cleanup temporary directory
FileUtils.rm_rf tmp_dir

