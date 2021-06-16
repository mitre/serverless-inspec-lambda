# frozen_string_literal: true

##
# Allows running the lambda function on your local development machine for
# testing purposes.
#
# bundle exec ruby ./run_lambda_locally.rb
#
# Allowable event parameters:
#    'profile'             => <url to InSpec profile>
#    'ssh_key_ssm_param'   => <path to SSM parameter that stores private key material>,
#    'profile_common_name' => <The 'common name' of the InSpec profile that will be used in filenames>,
#    'config'              => <Direct InSpec Configuration (see below)>
#        'target'     => <The target to run the profile against>
#        'sudo'       => <Indicates if can use sudo as the logged in user>
#        'input_file' => <location of an alternative inspec.yml configuration file for the profile>
#        'key_files'  => <A local key file to use when starting SSH session>
#
# What can I put in the 'target' argument?
#    (omitting this will run the profile on the local machine)
#    ssh://ec2-user@i-09f17fd0396d9c6f7
#    ssh://ec2-user@mi-09f17fd0396d9c6f7
#    ssh://ec2-user@someawsdnsname.aws.com
#

require_relative 'lambda_function'

lambda_handler(
  event: {
    "results_bucket" => "inspec-results-bucket-dev-28wd",
    "profile" => "https://github.com/mitre/microsoft-windows-server-2019-stig-baseline.git",
    "profile_common_name" => "microsoft-windows-server-2019-stig-baseline",
    "config" => {
      "target" => "winrm://i-0e35ab216355084ee", #ec2-160-1-5-36.us-gov-west-1.compute.amazonaws.com
      "user" => "Administrator",
      "password" => {
        "instance_id" => "i-0e35ab216355084ee",
        "launch_key" => "/inspec/test-ssh-key"
      }
    }
  },
  context: nil
)
