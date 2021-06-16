
require 'aws-sdk-lambda'
require 'aws-sdk-ssm'
require 'aws-sdk-s3'
require 'json'
require 'inspec'
require 'logger'

puts "RUBY_VERSION: #{RUBY_VERSION}"
$logger = Logger.new($stdout)

##
# The vanilla `dig` method will throw an exception if it hits a non-hash object
# and still has more levels to dig - for example: { a: 'test' }.dig(:a, :b, :c).
# 
# The `safe_dig` method will just return nil if `dig` throws an exception.
#
class Hash
  def safe_dig(*args)
    return dig(*args)
  rescue
    return nil
  end
end

##
# Entrypoint for the Serverless InSpec lambda functoin
#
# See the README for more information
#
def lambda_handler(event:, context:)
  # Set export filename
  filename, file_path = generate_json_file(event['profile_common_name'] || 'unnamed_profile')
  json_reporter = "json:" + file_path
  $logger.info("Will write JSON at #{file_path}")

  # Build the config we will use when executing InSpec
  config = build_config(event, file_path)

  # Define InSpec Runner
  $logger.info('Building InSpec runner.')
  runner = Inspec::Runner.new(config)

  # Set InSpec Target
  $logger.info('Adding InSpec target.')
  runner.add_target(event["profile"])

  # Trigger InSpec Scan
  $logger.info('Running InSpec.')
  runner.run

  # Push the results to S3
  # https://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/S3/Client.html
  # Consider allowing passing additional eval_tags through the event
  # Consider tagging with the account ID
  s3_client = Aws::S3::Client.new
  s3_client.put_object({
    body: StringIO.new({
      "data" => JSON.parse(File.read(file_path)),
      "eval_tags" => "ServerlessInspec"
    }.to_json), 
    bucket: event['results_bucket'], 
    key: "unprocessed/#{filename}", 
  }) unless event['results_bucket'].nil?
end

def get_account_id(context)
  aws_account_id = context.invoked_function_arn.split(":")[4]
  /^\d{12}$/.match?(aws_account_id)  ? aws_account_id : nil
end

##
# Generates the configuration that will be used for the InSpec execution
#
def build_config(event, file_path)
  # Call all builder helpers for various special configuration cases
  handle_winrm_password(event)
  handle_s3_profile(event)
  handle_s3_input_file(event)
  handle_secure_string_input_file(event)

  # Start with a default config and merge in the config that was passed into the lambda
  config = default_config.merge(event['config'] || {}).merge(forced_config(file_path))

  # Add private key to config if it is present
  ssh_key = fetch_ssh_key(event['ssh_key_ssm_param'])
  config["key_files"] = [ssh_key] unless ssh_key.nil?

  if /ssh:\/\/.+@m?i-[a-z0-9]{17}/.match? config['target'] 
    $logger.info('Using proxy SSM session to SSH to managed EC2 instance.')
    config["proxy_command"] = 'sh -c "aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters portNumber=%p"'
  end

  if /winrm:\/\/m?i-[a-z0-9]{17}/.match? config['target']
    $logger.info('Using port forwarded SSM session to WINRM to managed EC2 instance.')
    instance_id = /m?i-[a-z0-9]{17}/.match(config['target'])[0]
    Process.detach(spawn("aws ssm start-session --target #{instance_id} --document-name AWS-StartPortForwardingSession --parameters '{\"portNumber\":[\"5985\"], \"localPortNumber\":[\"5985\"]}'"))
    Process.detach(spawn("aws ssm start-session --target #{instance_id} --document-name AWS-StartPortForwardingSession --parameters '{\"portNumber\":[\"5986\"], \"localPortNumber\":[\"5986\"]}'"))
    config['target'] = 'winrm://localhost'
    $logger.info('Waiting 30 seconds.')
    sleep(30)
  end

  $logger.info("Built config: #{config}")
  config
end

##
# AWS EC2 Windows instances may have their password saved and encrypted with an SSH key.
#
# If the config password is a hash with 'instance_id' and 'launch_key' atttributes, then
# this method will attempt to fetch and decrypt the password, then set the password 
# attribute properly.
#
def handle_winrm_password(event)
  instance_id = event.safe_dig('config', 'password', 'instance_id')
  launch_key = event.safe_dig('config', 'password', 'launch_key')
  return if instance_id.nil? || launch_key.nil?

  $logger.info('Fetching winrm password for authentication.')
  file_path = '/tmp/launch_key'
  File.write(file_path, fetch_ssm_param(launch_key))

  password = JSON.parse(`aws ec2 get-password-data --instance-id #{instance_id} --priv-launch-key #{file_path}`)['PasswordData']
  event['config']['password'] = password
rescue
  return nil
end

##
# If "profile" is a zip from an S3 bucket (notated by "profile" being a hash)
# then we need to fetch the file and download it to /tmp/
#
# https://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/S3/Client.html
#
def handle_s3_profile(event)
  bucket = event.safe_dig("profile", "bucket")
  key = event.safe_dig("profile", "key")
  return if bucket.nil? || key.nil?

  unless key.end_with?('.zip') || key.end_with?('.tar.gz')
    $logger.error 'InSpec profiles from S3 are only supported as *.zip or *.tar.gz files!'
    exit 1
  end

  profile_download_path = '/tmp/inspec-profile.zip'
  $logger.info("Downloading InSpec profile to #{profile_download_path}")
  s3 = Aws::S3::Client.new
  s3.get_object({ bucket: bucket, key: key }, target: profile_download_path)

  event["profile"] = profile_download_path
end

##
# If "input_file" is located in an S3 bucket 
# (notated by "bucket" and "key" being present in the "input_file" parameter),
# then we need to fetch the file and download it to /tmp/
#
# https://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/S3/Client.html
#
def handle_s3_input_file(event)
  bucket = event.safe_dig("config", "input_file", "bucket")
  key = event.safe_dig("config", "input_file", "key")
  return if bucket.nil? || key.nil?

  input_file_download_path = '/tmp/input_file.yml'
  $logger.info("Downloading InSpec input_file to #{input_file_download_path}")
  s3 = Aws::S3::Client.new
  s3.get_object(
    { bucket: event["config"]["input_file"]["bucket"], key: event["config"]["input_file"]["key"] },
    target: input_file_download_path
  )

  event["config"]["input_file"] = [input_file_download_path]
end

##
# If "input_file" is located inside of an SSM SecureString parameter
# (notated by "ssm_secure_string" being present in the "input_file" parameter),
# then we need to fetch & decrypt the parameter and save it to /tmp/input_file.yml
#
# https://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/SSM/Client.html
#
def handle_secure_string_input_file(event)
  param = event.safe_dig("config", "input_file", "ssm_secure_string")
  return if param.nil?

  file_path = '/tmp/input_file.yml'
  File.write(file_path, fetch_ssm_param(param))

  # Update the event with the input_file
  event["config"]["input_file"] = [file_path]
end

##
# Helper to fetch and return an SSM parameter.
#
def fetch_ssm_param(param)
  # Either use the default client or a specified endpoint
  ssm_client = nil
  if ENV['SSM_ENDPOINT'].nil?
    $logger.info("Using default SSM Parameter Store endpoint.")
    ssm_client = Aws::SSM::Client.new
  else
    endpoint = "https://#{/vpce.+/.match(ENV['SSM_ENDPOINT'])[0]}"
    $logger.info("Using SSM Parameter Store endpoint: #{endpoint}")
    ssm_client = Aws::SSM::Client.new(endpoint: endpoint)
  end

  # Fetch and return the parameter
  resp = ssm_client.get_parameter({
    name: param,
    with_decryption: true,
  })
  $logger.info("Successfully fetched #{param} SSM Parameter.")
  resp.parameter.value
end

##
# Fetch the SSH key from SSM Parameter Store if the function execution requires it
#
# If ENV['SSM_ENDPOINT'] is set, then it will use that VPC endpoint to reach SSM.
#
# Params:
# - ssh_key_ssm_param:String The SSM Parameter identifier to fetch
#
# Returns:
# - nil if no key has been fetched, or path to key if downloaded.
#
def fetch_ssh_key(ssh_key_ssm_param)
  if ssh_key_ssm_param.nil? || ssh_key_ssm_param.empty?
    $logger.info('ssh_key_ssm_param is blank. Will not fetch SSH key.')
    return nil
  end

  ssm_client = nil
  if ENV['SSM_ENDPOINT'].nil?
    $logger.info("Using default SSM Parameter Store endpoint.")
    ssm_client = Aws::SSM::Client.new
  else
    endpoint = "https://#{/vpce.+/.match(ENV['SSM_ENDPOINT'])[0]}"
    $logger.info("Using SSM Parameter Store endpoint: #{endpoint}")
    ssm_client = Aws::SSM::Client.new(endpoint: endpoint)
  end
  resp = ssm_client.get_parameter({
    name: ssh_key_ssm_param,
    with_decryption: true,
  })
  file_path = '/tmp/id_rsa'
  File.write(file_path, resp.parameter.value)
  file_path
end

##
# This is the configuration that is absolutely necessary
# for the lambda to function properly
#
def forced_config(file_path)
  {
    "logger" => Logger.new(nil),
    "type" => :exec, 
    "reporter" => {
      "cli" => {
        "stdout" => true
      },
      "json" => {
        "file" => file_path,
        "stdout" => false
      }
    }
  }
end

##
# This is the configuration that is NOT absolutely necessary
# and can be overridden by configuration passed to the lambda
#
def default_config
  {
    "version" => "1.1",
    "cli_options" => {
      "color" => "true"
    },
    "show_progress" => false, 
    "color" => true, 
    "create_lockfile" => true, 
    "backend_cache" => true, 
    "enable_telemetry" => false, 
    "winrm_transport" => "negotiate", 
    "insecure" => false, 
    "winrm_shell_type" => "powershell", 
    "distinct_exit" => true, 
    "diff" => true, 
    "sort_results_by" => "file", 
    "filter_empty_profiles" => false, 
    "reporter_include_source" => false, 
    
  }
end


def generate_json_file(name)
  filename = "#{Time.now.strftime("%Y-%m-%d_%H-%M-%S")}_#{name}.json"
  file_path = '/tmp/' + filename
  return filename, file_path
end
