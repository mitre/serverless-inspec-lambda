# Serverless InSpec (AWS)

[![Static Analysis](https://github.com/mitre/serverless-inspec-lambda/actions/workflows/static.yml/badge.svg)](https://github.com/mitre/serverless-inspec-lambda/actions/workflows/static.yml)

This lambda function is meant to allow you to execute InSpec profiles in a serverless fashion. It strives to be as similar as it can be to how you would normally run `inspec exec` on your CLI, while also adding some useful functionality specific to AWS.

## Table of Contents
- [How can I deploy this lambda function?](#how-can-i-deploy-this-lambda-function)
- [Scan Configuration Examples](#scan-configuration-examples)
- [What does the `results_buckets` event attribute do?](#what-does-the-results_buckets-event-attribute-do)
- [What does the `command` event attribute do?](#what-does-the-command-event-attribute-do)
- [What does the `resources` event attribute do?](#what-does-the-resources-event-attribute-do)
- [What does the `env` event attribute do?](#what-does-the-env-event-attribute-do)
- [What does the `eval_tags` event attribute do?](#what-does-the-eval_tags-event-attribute-do)
- [What does the `results_name` event attribute do?](#what-does-the-results_name-event-attribute-do)
- [What does the `tmp_ssm_ssh_key` event attribute do?](#what-does-the-tmp_ssm_ssh_key-event-attribute-do)
- [What does the `ssm_port_forward` event attribute do?](#what-does-the-ssm_port_forward-event-attribute-do)
- [How can I run profiles with dependencies in an offline environment?](#how-can-i-run-profiles-with-dependencies-in-an-offline-environment)
- [How do I set up an SSM managed instance?](#how-do-i-set-up-an-ssm-managed-instance)
- [Scheduling Recurring Scans](#scheduling-recurring-scans)

## How can I deploy this lambda function?
For instructions on how to configure and deploy this Lambda function with Terraform, see [TF_EXAMPLE.md](./TF_EXAMPLE.md)

## Scan Configuration Examples
These are examples of the JSON that can be passed into the lambda event to obtain a successful scan. 

You can find more details on these configurations and additional configuration options in this README.

### AWS Resource Scanning
Note that if you are running InSpec AWS scans, then the lambda's IAM profile must have suffient permissions to analyze your environment.
```json
{
  "command": "inspec exec https://github.com/mitre/aws-foundations-cis-baseline/archive/master.tar.gz -t aws://",
  "results_name": "aws-foundations-cis-baseline",
  "results_buckets": [
    "inspec-results-bucket-dev"
  ],
  "eval_tags": "ServerlessInspec,AwsCisBaseline,AWS"
}
```

### RedHat 7 STIG Baseline (SSH)
```json
{
  "command": "inspec exec /tmp/redhat-enterprise-linux-7-stig-baseline-2.6.6.tar.gz -t ssh://ec2-user@ec2-15-200-235-74.us-gov-west-1.compute.amazonaws.com -i /tmp/id_rsa --sudo --input=disable_slow_controls=true",
  "results_name": "redhat-enterprise-linux-7-stig-baseline-inspec-rhel7-test",
  "results_buckets": [
    "inspec-results-bucket-dev"
  ],
  "eval_tags": "ServerlessInspec,RHEL7,inspec-rhel7-test,SSH",
  "resources": [
    {
      "local_file_path": "/tmp/redhat-enterprise-linux-7-stig-baseline-2.6.6.tar.gz",
      "source_aws_s3_bucket": "inspec-profiles-bucket-dev",
      "source_aws_s3_key": "redhat-enterprise-linux-7-stig-baseline-2.6.6.tar.gz"
    },
    {
      "local_file_path": "/tmp/id_rsa",
      "source_aws_ssm_parameter_key": "/inspec/rhel-7-test/id_rsa"
    }
  ]
}
```

### RedHat 7 STIG Baseline (SSH via SSM tunneled through SSM with a temporary SSH key)
The `--proxy_command` command line argument is tunneling the session through SSM. 

The `tmp_ssm_ssh_key` defines attributes around a temporary SSH key that will be generated and disposed of during the lifetime of the function execution, which provides temporary access (in a 60 second window) to the SSM managed instance for the function.
```json
{
  "command": "inspec exec https://github.com/mitre/redhat-enterprise-linux-7-stig-baseline/archive/master.tar.gz -t ssh://ssm-user@i-00f1868f8f3b4eb03 -i /tmp/tmp_ssh_key --input=disable_slow_controls=true --proxy-command='sh -c \"aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters portNumber=%p\"'",
  "results_name": "redhat-enterprise-linux-7-stig-baseline-inspec-rhel7-test",
  "results_buckets": [
    "inspec-results-bucket-dev"
  ],
  "eval_tags": "ServerlessInspec,RHEL7,inspec-rhel7-test,SSH-SSM",
  "tmp_ssm_ssh_key": {
    "host": "i-00f1868f8f3b4eb03",
    "user": "ssm-user",
    "key_name": "tmp_ssh_key"
  }
}
```

### RedHat 7 STIG Baseline (SSM Send Command with awsssm:// transport)
```json
{
  "command": "inspec exec https://github.com/mitre/redhat-enterprise-linux-7-stig-baseline/archive/master.tar.gz -t awsssm://i-00f1868f8f3b4eb03 --input=disable_slow_controls=true",
  "results_name": "redhat-enterprise-linux-7-stig-baseline-inspec-rhel7-test",
  "results_buckets": [
    "inspec-results-bucket-dev"
  ],
  "eval_tags": "ServerlessInspec,RHEL7,inspec-rhel7-test,AWSSSM"
}
```

### Windows Server 2019 STIG Baseline (WinRM via SSM Port Forwarding)
Note that the target is set to `winrm://localhost` because port forwarding is being set up with the `ssm_port_forward` event property.
```json
{
  "command": "inspec exec /tmp/microsoft-windows-server-2019-stig-baseline-1.3.10.tar.gz -t winrm://localhost --password $WIN_PASS",
  "results_name": "windows-server-2019-stig-baseline-inspec-win2019-test",
  "results_buckets": [
    "inspec-results-bucket-dev"
  ],
  "eval_tags": "ServerlessInspec,WinSvr2019,inspec-win2019-test,WinRM",
  "resources": [
    {
      "local_file_path": "/tmp/microsoft-windows-server-2019-stig-baseline-1.3.10.tar.gz",
      "source_aws_s3_bucket": "inspec-profiles-bucket-dev",
      "source_aws_s3_key": "microsoft-windows-server-2019-stig-baseline-1.3.10.tar.gz"
    },
    {
      "env_variable": "WIN_PASS",
      "source_aws_secrets_manager_secret_name": "/inspec/inspec-win2019-test/password"
    }
  ],
  "ssm_port_forward": {
    "instance_id": "i-0e35ab216355084ee",
    "ports": [5985, 5986]
  }
}
```

### Windows Server 2019 STIG Baseline (SSM Send Command with awsssm:// transport)
```json
{
  "command": "inspec exec /tmp/microsoft-windows-server-2019-stig-baseline-1.3.10.tar.gz -t awsssm://i-00f1868f8f3b4eb03",
  "results_name": "windows-server-2019-stig-baseline-inspec-win2019-test",
  "results_buckets": [
    "inspec-results-bucket-dev"
  ],
  "eval_tags": "ServerlessInspec,WinSvr2019,inspec-win2019-test,AWSSSM",
  "resources": [
    {
      "local_file_path": "/tmp/microsoft-windows-server-2019-stig-baseline-1.3.10.tar.gz",
      "source_aws_s3_bucket": "inspec-profiles-bucket-dev",
      "source_aws_s3_key": "microsoft-windows-server-2019-stig-baseline-1.3.10.tar.gz"
    },
  ],
}
```

### Kubernetes (with k8s:// transport)
```json
{
  "command": "inspec exec https://gitlab.dsolab.io/scv-content/inspec/kubernetes/baselines/k8s-cluster-stig-baseline/-/archive/master/k8s-cluster-stig-baseline-master.tar.gz -t k8s://",
  "results_name": "k8s-cluster-stig-baseline-dev-cluster",
  "results_buckets": [
    "inspec-results-bucket-dev"
  ],
  "eval_tags": "ServerlessInspec,k8s",
  "resources": [
    {
      "local_file_path": "/tmp/kube/config",
      "source_aws_s3_bucket": "inspec-profiles-bucket-dev",
      "source_aws_s3_key": "kube-dev/config"
    },
    {
      "local_file_path": "/tmp/kube/client.crt",
      "source_aws_ssm_parameter_key": "/inspec/kube-dev/client_crt"
    },
    {
      "local_file_path": "/tmp/kube/client.key",
      "source_aws_ssm_parameter_key": "/inspec/kube-dev/client_key"
    },
    {
      "local_file_path": "/tmp/kube/ca.crt",
      "source_aws_ssm_parameter_key": "/inspec/kube-dev/ca_crt"
    }
  ],
  "env": {
    "KUBECONFIG": "/tmp/kube/config"
  }
}
```

### PostgreSQL 12 STIG Baseline (TODO)
Database scans have not been tested yet with this lambda function.
```json
"https://github.com/mitre/aws-rds-crunchy-data-postgresql-9-stig-baseline"
```

## What does the `results_buckets` event attribute do?
The `results_buckets` event attribute defines S3 buckets that the function will push JSON results to.

If you DO NOT specify the `results_buckets` parameter in the lambda event, then the results will just be logged to CloudWatch. If you DO specify the `results_buckets` parameter in the lambda event, then the lambda will attempt to save the results JSON to the S3 bucket under `unprocessed/*`. The format of the JSON is meant to be a incomplete API call to push results to a Heimdall Server and looks like this:
```javascript
{
  "data": {}, // this contains the HDF results
  "eval_tags": "<eval_tags from event attribute>"
}
```

The `results_bucket` event parameter format looks like the following:
```json
{
  "...": "...",
  "results_buckets": [
    "inspec-results-bucket-dev"
  ]
}
```

## What does the `command` event attribute do?
The `command` event attribute defines the inspec exec command that the lambda function will execute. Note that ` --show-progress --reporter cli json:<results_name>` will be appended to the end of the `command` attribute before execution.

This __MUST__ be an `inspec exec` command. [Read more about inspec exec here](https://docs.chef.io/inspec/cli/#exec)

```json
{
  "command": "inspec exec /tmp/redhat-enterprise-linux-7-stig-baseline-2.6.6.tar.gz -t ssh://root@host -i /tmp/id_rsa --sudo --input=disable_slow_controls=true",
  "...": "..."
}
```

## What does the `resources` event attribute do?
The `resources` event attribute defines what files and/or environment variables are needed prior to executing the InSpec command. This might be a tar.gz of an InSpec profile stored in S3, a Windows password stored in SSM Parameter store, etc.

You may define a resources as needing to be downloaded as a local file on disk (must be located within `/tmp/`), or as needing have their contents stored in an environment variable. Downloaded files and environment variable resources will be usable by your `inspec exec ...` command.

### Local File Resource
```json
{
  "resources": [
    {
      "local_file_path": "/tmp/microsoft-windows-server-2019-stig-baseline-1.3.10.tar.gz",
      "...": "...",
    }
  ],
}
```

### Environment Variable Resource
```json
{
  "resources": [
    {
      "env_variable": "WIN_PASS",
      "...": "..."
    }
  ],
}
```

The possible sources for the lamdba's `resources` are defined below:

### S3 Resources
Resources may be downloaded from an S3 bucket. Ensure that you lambda's IAM role has `s3:getObject` permissions for the desired bucket/object.
```json
{
  "resources": [
    {
      "...": "...",
      "source_aws_s3_bucket": "inspec-profiles-bucket-dev",
      "source_aws_s3_key": "microsoft-windows-server-2019-stig-baseline-1.3.10.tar.gz"
    },
  ]
}
```

### AWS SSM Parameter Store Resources
Resources may be fetched from AWS SSM Parameter Store. Ensure that you lambda's IAM role has `kms:Decrypt` permissions for the secrets's KMS key and has `ssm:GetParameter` permissions for the parameter.

```json
{
  "resources": [
    {
      "...": "...",
      "source_aws_ssm_parameter_key": "/inspec/kube-dev/client_crt"
    }
  ]
}
```

### AWS Secrets Manager Resources
Resources may be fetched from AWS Secrets Manager. Ensure that you lambda's IAM role has `kms:Decrypt` permissions for the secrets's KMS key and `secretsmanager:GetSecretValue` permissions for the secret.
```json
{
  "resources": [
    {
      "...": "...",
      "source_aws_secrets_manager_secret_name": "/inspec/kube-dev/client_crt"
    }
  ]
}
```

## What does the `env` event attribute do?
The `env` event attribute allows definition of static envrionment variables that are needed by the InSpec command. Note that you may not overwrite an existing environment varaible.
```json
{
  "...": "...",
  "env": {
    "KUBECONFIG": "/tmp/kube/config",
    "OTHER_ENV": "value"
  }
}
```

## What does the `eval_tags` event attribute do?
The `eval_tags` event attribute allows definition of comma separated Heimdall `eval_tags` that will be passed through to the results file.
```json
{
  "...": "...",
  "eval_tags": "hostname,profile,etc"
}
```

## What does the `results_name` event attribute do?
The `results_name` event attribute defines the filename for generated InSpec scan results. If this is not set, then the `results_name` will default to `unnamed_profile`.
```json
{
  "...": "...",
  "results_name": "human-readable-name-of-my-results"
}
```

## What does the `tmp_ssm_ssh_key` event attribute do?
The `tmp_ssm_ssh_key` event attribute allows the function to push temporary SSH keys to a linux-based SSM managed instance. These keys are generated as needed and are disposed of on the target machine after 60 seconds.

This method of InSpec scanning works with the following sequence of events:
1. Generate a SSH key pair within the lambda function
2. Use the [train-awsssm](https://github.com/tecracer-chef/train-awsssm) plugin to send the public key material to `~/.ssh/authorized_keys` using [SSM Send Command](https://docs.aws.amazon.com/sdk-for-ruby/v3/api/Aws/SSM/Client.html#send_command-instance_method)
3. Immedately queue another SSM Send Command to remove the key from `~/.ssh/authorized_keys` after 60 seconds
4. Start an SSH session using the generated key pair and execute the InSpec scan over SSH

Assumptions with this method:
- Scanning linux-based instances (i.e. not Windows)
- The instance has the following commands installed: `su`, `mkdir`, `touch`, `echo`, `sleep`, `grep`, `mv`
- The user that runs "SSM Send Command" commands is priviledged to write to any user's `~/.ssh` directory (this should default to root unless explicitly changed)

This method is advantageous over using the `awsssm://` transport by itself because invoking all InSpec commands over SSM Send Command is significantly slower than over SSH.
```json
{
  "...": "...",
  "tmp_ssm_ssh_key": {
    "host": "i-00f1868f8f3b4eb03",
    "user": "ssm-user",
    "key_name": "tmp_ssh_key"
  }
}
```

## What does the `ssm_port_forward` event attribute do?
The `tmp_ssm_ssh_key` event attribute defines local ports to be forwarded to a specific SSM managed instance. This is useful if the lambda function does not have direct network access to the machine, but both the lambda and machine have access to SSM.

Note that forwarding local ports will mean that you will need to connect to `localhost` for your inspec exec command (e.g., `inspec exec ... -t winrm://localhost`)

```json
{
  "...": "...",
  "ssm_port_forward": {
    "instance_id": "i-0e35ab216355084ee",
    "ports": [5985, 5986]
  }
}
```

## How can I run profiles with dependencies in an offline environment?
The recommendation for offline environments is to save vendored InSpec profiles to an S3 bucket.

```bash
git clone git@github.com:mitre/aws-foundations-cis-baseline.git
inspec vendor ./aws-foundations-cis-baseline && inspec archive ./aws-foundations-cis-baseline
# Then upload ./aws-foundations-cis-baseline.tar.gz to you S3 bucket
```

## How Do I Set Up an SSM Managed Instance?
You can make an EC2 instance a SSM managed instance using [this guide](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-setting-up.html). This also requires that your EC2 instance has the SSM agent software installed on it. Some AWS-provided images already have this installed, but if it is not already installed on you instance then you can use [this guide](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-setting-up.html) to get it installed.

## Scheduling Recurring Scans
The recommended way to set up recurring scans is to create an Event Rule within AWS CloudWatch.

You can do this via the AWS Console using the following steps:
1. Navigate to the CloudWatch service and click `rules` on the left-hand side
2. Click the `Create Rule` button
3. Instead of `Event Pattern`, chosse the `Schedule` option and either use CRON or a standard schedule confugration
4. Click `Add a Target` with the type of `Lambda Function` and select the Serverless InSpec function
5. Expand `Configure Input` and choose `Constant (JSON text)`
6. Paste your configuration into the `Constant (JSON text)` field (this will be passed to the lambda event each time it is triggered)

### NOTICE

© 2019-2021 The MITRE Corporation.

Approved for Public Release; Distribution Unlimited. Case Number 18-3678.

### NOTICE

MITRE hereby grants express written permission to use, reproduce, distribute, modify, and otherwise leverage this software to the extent permitted by the licensed terms provided in the LICENSE.md file included with this project.

### NOTICE

This software was produced for the U. S. Government under Contract Number W56KGU-18-D-0004, and is subject to Federal Acquisition Regulation Clause 52.227-14, Rights in Data-General.

No other use other than that granted to the U. S. Government, or to those acting on behalf of the U. S. Government under that Clause is authorized without the express written permission of The MITRE Corporation.

