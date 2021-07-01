# frozen_string_literal: true

##
# Allows running the lambda function on your local development machine for
# testing purposes.
#
# bundle exec ruby ./run_lambda_locally.rb
#

require_relative 'lambda_function'

lambda_handler(
  event: {
    'results_bucket' => 'inspec-results-bucket-dev-28wd',
    'profile' => 'https://github.com/mitre/redhat-enterprise-linux-7-stig-baseline/archive/master.tar.gz',
    'profile_common_name' => 'rhel7-stig-testing',
    'config' => {
      'target' => 'awsssm://i-00f1868f8f3b4eb03',
      'input' => [
        'disable_slow_controls=true'
      ],
      'sudo' => true
    }
  },
  context: nil
)
