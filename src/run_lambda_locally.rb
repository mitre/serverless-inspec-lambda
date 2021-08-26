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
    'command' => 'inspec exec https://gitlab.dsolab.io/scv-content/inspec/kubernetes/baselines/k8s-cluster-stig-baseline/-/archive/master/k8s-cluster-stig-baseline-master.tar.gz'\
                 ' -t k8s://',
    'results_name' => 'k8s-cluster-stig-baseline-dev-cluster',
    'results_buckets' => [
      'inspec-results-bucket-dev'
    ],
    'eval_tags' => 'ServerlessInspec,k8s',
    'resources' => [
      {
        'local_file_path' => '/tmp/kube/config',
        'source_aws_s3_bucket' => 'inspec-profiles-bucket-dev',
        'source_aws_s3_key' => 'kube-dev/config'
      },
      {
        'local_file_path' => '/tmp/kube/client.crt',
        'source_aws_ssm_parameter_key' => '/inspec/kube-dev/client_crt'
      },
      {
        'local_file_path' => '/tmp/kube/client.key',
        'source_aws_ssm_parameter_key' => '/inspec/kube-dev/client_key'
      },
      {
        'local_file_path' => '/tmp/kube/ca.crt',
        'source_aws_ssm_parameter_key' => '/inspec/kube-dev/ca_crt'
      }
    ],
    'env' => {
      'KUBECONFIG' => '/tmp/kube/config'
    }
  },
  context: nil
)

# SSH command
_ = {
  'command' => 'inspec exec /tmp/redhat-enterprise-linux-7-stig-baseline-2.6.6.tar.gz'\
               ' -t ssh://ec2-user@ec2-15-200-235-74.us-gov-west-1.compute.amazonaws.com'\
               ' --sudo'\
               ' --input=disable_slow_controls=true',
  'results_name' => 'redhat-enterprise-linux-7-stig-baseline-inspec-rhel7-test',
  'results_buckets' => [
    'inspec-results-bucket-dev'
  ],
  'eval_tags' => 'ServerlessInspec,RHEL7,inspec-rhel7-test,SSH',
  'resources' => [
    {
      'local_file_path' => '/tmp/redhat-enterprise-linux-7-stig-baseline-2.6.6.tar.gz',
      'source_aws_s3_bucket' => 'inspec-profiles-bucket-dev',
      'source_aws_s3_key' => 'redhat-enterprise-linux-7-stig-baseline-2.6.6.tar.gz'
    }
  ]
}

# SSH via SSM command (with tmp key)
_ = {
  'command' => 'inspec exec https://github.com/mitre/redhat-enterprise-linux-7-stig-baseline/archive/master.tar.gz'\
               ' -t ssh://ssm-user@i-00f1868f8f3b4eb03'\
               ' -i /tmp/tmp_ssh_key'\
               ' --input=\'disable_slow_controls=true\''\
               ' --proxy-command=\'sh -c "aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters portNumber=%p"\'',
  'results_name' => 'redhat-enterprise-linux-7-stig-baseline-inspec-rhel7-test',
  'results_buckets' => [
    'inspec-results-bucket-dev'
  ],
  'eval_tags' => 'ServerlessInspec,RHEL7,inspec-rhel7-test,SSH-SSM',
  'tmp_ssm_ssh_key' => {
    'host' => 'i-00f1868f8f3b4eb03',
    'user' => 'ssm-user',
    'key_name' => 'tmp_ssh_key'
  }
}

# AWSSSM command
_ = {
  'command' => 'inspec exec https://github.com/mitre/redhat-enterprise-linux-7-stig-baseline/archive/master.tar.gz'\
               ' -t awsssm://i-00f1868f8f3b4eb03'\
               ' --input=\'disable_slow_controls=true\'',
  'results_name' => 'redhat-enterprise-linux-7-stig-baseline-inspec-rhel7-test',
  'results_buckets' => [
    'inspec-results-bucket-dev'
  ],
  'eval_tags' => 'ServerlessInspec,RHEL7,inspec-rhel7-test,AWSSSM'
}

# WinRM command
_ = {
  'command' => 'inspec exec /tmp/microsoft-windows-server-2019-stig-baseline-1.3.10.tar.gz'\
               ' -t winrm://localhost'\
               ' --password $WIN_PASS',
  'results_name' => 'windows-server-2019-stig-baseline-inspec-win2019-test',
  'results_buckets' => [
    'inspec-results-bucket-dev'
  ],
  'eval_tags' => 'ServerlessInspec,WinSvr2019,inspec-win2019-test,WinRM',
  'resources' => [
    {
      'local_file_path' => '/tmp/microsoft-windows-server-2019-stig-baseline-1.3.10.tar.gz',
      'source_aws_s3_bucket' => 'inspec-profiles-bucket-dev',
      'source_aws_s3_key' => 'microsoft-windows-server-2019-stig-baseline-1.3.10.tar.gz'
    },
    {
      'env_variable' => 'WIN_PASS',
      'source_aws_ssm_parameter_key' => '/inspec/inspec-win2019-test/password'
    }
  ],
  'ssm_port_forward' => {
    'instance_id' => 'i-0e35ab216355084ee',
    'ports' => [5985, 5986]
  }
}

# AWS CIS Baseline command
_ = {
  'command' => 'inspec exec /tmp/aws-foundations-cis-baseline-1.2.2.tar.gz'\
               ' -t aws://',
  'results_name' => 'aws-foundations-cis-baseline-6756-0937-9314',
  'results_buckets' => [
    'inspec-results-bucket-dev'
  ],
  'eval_tags' => 'ServerlessInspec,AwsCisBaseline,6756-0937-9314,AWS',
  'resources' => [
    {
      'local_file_path' => '/tmp/aws-foundations-cis-baseline-1.2.2.tar.gz',
      'source_aws_s3_bucket' => 'inspec-profiles-bucket-dev',
      'source_aws_s3_key' => 'aws-foundations-cis-baseline-1.2.2.tar.gz'
    }
  ]
}

# k8s command
_ = {
  'command' => 'inspec exec https://gitlab.dsolab.io/scv-content/inspec/kubernetes/baselines/k8s-cluster-stig-baseline/-/archive/master/k8s-cluster-stig-baseline-master.tar.gz'\
               ' -t k8s://',
  'results_name' => 'k8s-cluster-stig-baseline-dev-cluster',
  'results_buckets' => [
    'inspec-results-bucket-dev'
  ],
  'eval_tags' => 'ServerlessInspec,k8s',
  'resources' => [
    {
      'local_file_path' => '/tmp/kube/config',
      'source_aws_s3_bucket' => 'inspec-profiles-bucket-dev',
      'source_aws_s3_key' => 'kube-dev/config'
    },
    {
      'local_file_path' => '/tmp/kube/client.crt',
      'source_aws_ssm_parameter_key' => '/inspec/kube-dev/client_crt'
    },
    {
      'local_file_path' => '/tmp/kube/client.key',
      'source_aws_ssm_parameter_key' => '/inspec/kube-dev/client_key'
    },
    {
      'local_file_path' => '/tmp/kube/ca.crt',
      'source_aws_ssm_parameter_key' => '/inspec/kube-dev/ca_crt'
    }
  ],
  'env' => {
    'KUBECONFIG' => '/tmp/kube/config'
  }
}
