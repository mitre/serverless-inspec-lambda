# frozen_string_literal: true

require 'aws-sdk-lambda'
require 'aws-sdk-ssm'
require 'aws-sdk-s3'
require 'json'
require 'inspec'
require 'inspec/cli'
require 'logger'
require 'shellwords'
require 'train-awsssm'

puts "RUBY_VERSION: #{RUBY_VERSION}"
$logger = Logger.new($stdout)

Encoding.default_external = Encoding::UTF_8
Encoding.default_internal = Encoding::UTF_8

##
# The current train-awsssm gem does not implement file_via_connection.
# This patch is meant to implement it in a minimal manner.
#
module TrainPlugins
  module AWSSSM
    # Patch existing class in https://github.com/tecracer-chef/train-awsssm
    class Connection < Train::Plugins::Transport::BaseConnection
      def file_via_connection(path)
        windows_instance? ? Train::File::Remote::Windows.new(self, path) : Train::File::Remote::Unix.new(self, path)
      end
    end
  end
end

##
# Entrypoint for the Serverless InSpec lambda function
#
# See the README for more information
#
# rubocop:disable Lint/UnusedMethodArgument
def lambda_handler(event:, context:)
  # Set export filename
  filename, file_path = generate_json_file(event['results_name'] || 'unnamed_profile')
  $logger.info("Will write JSON at #{file_path}")

  # Validate and make modifcations to the InSpec command
  inspec_cmd = event['command'] + " --show-progress --reporter cli json:#{file_path}"
  raise(StandardError, "Expected command to start with 'inspec exec ' but got: #{inspec_cmd}") if inspec_cmd[/^\s*inspec\s+exec\s+/].nil?

  # Resources and ENV setup
  configure_event_env(event['env']) unless event['env'].nil?
  fetch_resources(event['resources']) unless event['resources'].nil?
  push_tmp_ssh_key_to_instance(event['tmp_ssm_ssh_key']) unless event['tmp_ssm_ssh_key'].nil?
  setup_ssm_port_forward(event['ssm_port_forward']) unless event['ssm_port_forward'].nil?

  # ENV replacement in inspec_cmd
  env_inspec_cmd = inspec_cmd
  ENV.each { |key, value| env_inspec_cmd.gsub!("$#{key}", value) }

  # Execute InSpec
  # https://ruby-doc.org/core-2.3.0/Kernel.html#method-i-system
  $logger.info("Executing InSpec command: #{inspec_cmd}")
  success = system('bundle', *(['exec'] + Shellwords.split(env_inspec_cmd)))
  $logger.info("InSpec exec completed! Success: #{success.nil? ? 'nil (command might not be found)' : success}")

  return if event['results_buckets'].nil? || event['results_buckets'].empty?

  # Push the results to S3
  # https://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/S3/Client.html
  # Consider allowing passing additional eval_tags through the event
  # Consider tagging with the account ID
  event['results_buckets'].each do |bucket|
    $logger.info("Pushing results to S3 bucket: #{bucket}")
    s3_client = Aws::S3::Client.new
    s3_client.put_object(
      {
        body: StringIO.new({
          'data' => JSON.parse(File.read(file_path)),
          'eval_tags' => event['eval_tags'] || 'ServerlessInspec'
        }.to_json),
        bucket: bucket,
        key: "unprocessed/#{filename}"
      }
    )
  end
end
# rubocop:enable Lint/UnusedMethodArgument

def configure_event_env(env)
  $logger.info('Configuring ENV defined in event..')
  env.each { |k, v| set_env(k, v) }
end

##
# Simple helper to re-use logic that we should not overwrite ENV variables that already exist
#
def set_env(name, value)
  is_env_already_set = !ENV[name].nil?
  raise(StandardError, "Could overwrite existing ENV variable: #{name}") if is_env_already_set

  ENV[name] = value
end

def fetch_resources(resources)
  $logger.info('Fetching all resources defined in event...')
  resources.map { |r| fetch_resource(r) }
end

def fetch_resource(resource)
  # Determine the destination resource type
  is_file_download_dest = !resource['local_file_path'].nil?
  is_env_variable_dest = !resource['env_variable'].nil?

  local_file_path = force_tmp_local_file_path(resource['local_file_path']) if is_file_download_dest

  # Determine the source resource type
  is_s3_bucket_resource = !(resource['source_aws_s3_bucket'].nil? || resource['source_aws_s3_key'].nil?)
  is_ssm_parameter_resource = !resource['source_aws_ssm_parameter_key'].nil?
  is_secrets_manager_resource = !resource['source_aws_secrets_manager_secret_name'].nil?

  # Perform the fetch
  if is_s3_bucket_resource
    fetch_s3_bucket_resource(resource, local_file_path, is_file_download_dest, is_env_variable_dest)
  elsif is_ssm_parameter_resource
    fetch_ssm_parameter_resource(resource, local_file_path, is_file_download_dest, is_env_variable_dest)
  elsif is_secrets_manager_resource
    fetch_secrets_manager_resource(resource, local_file_path, is_file_download_dest, is_env_variable_dest)
  else
    raise(StandardError, "Could not fetch invalid resource definition: #{resource}")
  end
end

def fetch_ssm_parameter_resource(resource, local_file_path, is_file_download_dest, is_env_variable_dest)
  $logger.info('Fetching SSM resource...')
  # Either use the default client or a specified endpoint
  ssm_client = nil
  if ENV['SSM_ENDPOINT'].nil?
    $logger.info('Using default SSM Parameter Store endpoint.')
    ssm_client = Aws::SSM::Client.new
  else
    endpoint = "https://#{/vpce.+/.match(ENV['SSM_ENDPOINT'])[0]}"
    $logger.info("Using SSM Parameter Store endpoint: #{endpoint}")
    ssm_client = Aws::SSM::Client.new(endpoint: endpoint)
  end

  # Fetch and return the parameter
  resp = ssm_client.get_parameter(
    {
      name: resource['source_aws_ssm_parameter_key'],
      with_decryption: true
    }
  )

  if is_file_download_dest
    File.write(local_file_path, resp.parameter.value)
  elsif is_env_variable_dest
    set_env(resource['env_variable'], resp.parameter.value)
  else
    raise(StandardError, "Could not determine local destination for resource definition: #{resource}")
  end
end

def fetch_secrets_manager_resource(resource, local_file_path, is_file_download_dest, is_env_variable_dest)
  $logger.info('Fetching Secrets Manager resource...')
  secrets_manager_client = nil
  if ENV['SECRETS_MANAGER_ENDPOINT'].nil?
    $logger.info('Using default Secrets Manager endpoint.')
    secrets_manager_client = Aws::SecretsManager::Client.new
  else
    endpoint = "https://#{/vpce.+/.match(ENV['SECRETS_MANAGER_ENDPOINT'])[0]}"
    $logger.info("Using Secrets Manager endpoint: #{ENV['SECRETS_MANAGER_ENDPOINT']}")
    secrets_manager_client = Aws::SecretsManager::Client.new(endpoint: endpoint)
  end
  resp = secrets_manager_client.get_secret_value({ secret_id: resource['source_aws_secrets_manager_secret_name'] })

  # Write to the destination
  if is_file_download_dest
    File.write(local_file_path, resp.secret_string)
  elsif is_env_variable_dest
    set_env(resource['env_variable'], resp.secret_string)
  else
    raise(StandardError, "Could not determine local destination for resource definition: #{resource}")
  end
end

def fetch_s3_bucket_resource(resource, local_file_path, is_file_download_dest, is_env_variable_dest)
  $logger.info('Fetching S3 resource...')
  s3_client = Aws::S3::Client.new
  if is_file_download_dest
    s3_client.get_object({ bucket: resource['source_aws_s3_bucket'], key: resource['source_aws_s3_key'] },
                         target: local_file_path)
  elsif is_env_variable_dest
    resp = s3.get_object(bucket: resource['source_aws_s3_bucket'], key: resource['source_aws_s3_key'])
    set_env(resource['env_variable'], resp.body.read)
  else
    raise(StandardError, "Could not determine local destination for resource definition: #{resource}")
  end
end

##
# In lambda functions we expect /tmp to be the only writable directory on the filesystem.
# This method should ensure that the path only be withi /tmp/
#
def force_tmp_local_file_path(local_file_path)
  local_file_path = File.expand_path(local_file_path)
  # Ensure `dir_name` starts with "/tmp/"
  local_file_path = "/tmp/#{dir_name}" unless local_file_path.start_with?('/tmp/')

  # Ensure that any subdir of "/tmp/" exists
  FileUtils.mkdir_p(File.dirname(local_file_path))

  local_file_path
end

def generate_json_file(name)
  filename = "#{Time.now.strftime('%Y-%m-%d_%H-%M-%S')}_#{name}.json"
  file_path = "/tmp/#{filename}"
  [filename, file_path]
end

def setup_ssm_port_forward(ssm_port_forward)
  $logger.info("Using port forwarded SSM session for #{ssm_port_forward['instance_id']} on ports #{ssm_port_forward['ports']}.")
  ssm_port_forward['ports'].each do |port|
    Process.detach(
      spawn(
        "aws ssm start-session --target #{ssm_port_forward['instance_id']} --document-name AWS-StartPortForwardingSession"\
        " --parameters '{\"portNumber\":[\"#{port}\"], \"localPortNumber\":[\"#{port}\"]}'"
      )
    )
  end
  $logger.info('Waiting 15 seconds to ensure forwarded ports take effect.')
  sleep(15)
end

def push_tmp_ssh_key_to_instance(tmp_ssm_ssh_key)
  $logger.info('SSH via SSM will use a temporary key pair.')
  _, pub_key_path = generate_key_pair(tmp_ssm_ssh_key['key_name'])
  add_tmp_ssh_key(tmp_ssm_ssh_key, File.read(pub_key_path))
end

##
# Generate an SSH key pair and return the path to the public and private key files
#
def generate_key_pair(key_name = nil)
  $logger.info("Generating SSH key pair at /tmp/#{key_name}")
  key_name ||= 'id_rsa'
  `rm -f /tmp/#{key_name}*`
  priv_key_path = "/tmp/#{key_name}"
  pub_key_path = "/tmp/#{key_name}.pub"
  # shell out to ssh-keygen
  `ssh-keygen -f #{priv_key_path} -N ''`

  [priv_key_path, pub_key_path]
end

##
# Temporarily add a pubic key to a target managed instance for use over SSH.
#
# params:
# - host (string) The host ip or ID such as 'i-0e35ab216355084ee'
# - pub_key (string) The public key material
# - rm_wait (int) How long to keep the key active on the target system
#
def add_tmp_ssh_key(tmp_ssm_ssh_key, pub_key)
  $logger.info('Adding temporary SSH key pair to instance')
  user = tmp_ssm_ssh_key['user']
  host = tmp_ssm_ssh_key['host']
  rm_wait = 60
  exec_timeout = rm_wait + 30
  pub_key = pub_key.strip
  train = Train.create(
    'awsssm',
    { host: host, logger: Logger.new($stdout, level: :info), execution_timeout: exec_timeout }
  )
  conn = train.connection

  home_dir = conn.run_command("sudo -u #{user} sh -c 'echo $HOME'").stdout.strip

  put_cmd = "mkdir -p #{home_dir}/.ssh;"\
            " touch #{home_dir}/.ssh/authorized_keys;"\
            " echo '#{pub_key}' >> #{home_dir}/.ssh/authorized_keys;"

  rm_cmd = "sleep #{rm_wait};"\
           " grep -vF '#{pub_key}' #{home_dir}/.ssh/authorized_keys > #{home_dir}/.ssh/authorized_keys.tmp;"\
           " mv #{home_dir}/.ssh/authorized_keys.tmp #{home_dir}/.ssh/authorized_keys"

  puts "cmd result: #{conn.run_command(put_cmd)}"

  Thread.new do
    puts "remove result: #{conn.run_command(rm_cmd)}"
    conn.close
    $logger.info('Removed temporary SSH key pair from instance.')
  end
end
