# Serverless InSpec (AWS)

[![Static Analysis](https://github.com/mitre/serverless-inspec-lambda/actions/workflows/static.yml/badge.svg)](https://github.com/mitre/serverless-inspec-lambda/actions/workflows/static.yml)

This lambda function is meant to allow you to execute InSpec profiles in a serverless fashion. It strives to be as similar as it can be to how you would normally run `inspec exec` on your CLI, while also adding some useful functionality specific to AWS.

## Table of Contents
- [How Can I Deploy this Lambda Function?](#how-can-i-deploy-this-lambda-function)
- [Scan Configuration Examples](#scan-configuration-examples)
- [Where Do The Results Go?](#where-do-the-results-go)
- [How Do I Store and Specify an SSH Key for a Scan?](#how-do-i-store-and-specify-an-ssh-key-for-a-scan)
- [How can I specify `--target`?](#how-can-i-specify---target)
- [How can I specify which profile to execute?](#how-can-i-specify-which-profile-to-execute)
- [How can I run profiles with dependencies in an offline environment?](#how-can-i-run-profiles-with-dependencies-in-an-offline-environment)
- [How can I specify `--input-file`?](#how-can-i-specify---input-file)
- [How can I Specify `--input`?](#how-can-i-specify---input)
- [What other kinds of configurations can I specify?](#what-other-kinds-of-configurations-can-i-specify)
- [Where Can I Read More about the InSpec Config?](#where-can-i-read-more-about-the-inspec-config)
- [Scheduling Recurring Scans](#scheduling-recurring-scans)

## How Can I Deploy this Lambda Function?
For instructions on how to configure and deploy this Lambda function, see [EXAMPLE.md](./EXAMPLE.md)

## Scan Configuration Examples
These are examples of the JSON that can be passed into the lambda event to obtain a successful scan. 

You can find more details on these configurations and additional configuration options in this README.

### AWS Resource Scanning
Note that if you are running InSpec AWS scans, then the lambda's IAM profile must have suffient permissions to analyze your environment.
```json
{
  "results_bucket": "inspec-results-bucket",
  "profile": "https://github.com/mitre/aws-foundations-cis-baseline/archive/refs/heads/master.zip",
  "profile_common_name": "demo-aws-baseline-master",
  "config": {
    "target": "aws://"
  }
}
```

### RedHat 7 STIG Baseline (SSH)
```json
{
  "results_bucket": "inspec-results-bucket",
  "ssh_key_ssm_param": "/inspec/test-ssh-key",
  "profile": {
    "bucket": "inspec-profiles-bucket",
    "key": "redhat-enterprise-linux-7-stig-baseline-master.zip"
  },
  "profile_common_name": "redhat-enterprise-linux-7-stig-baseline-master",
  "config": {
    "target": "ssh://ec2-user@ec2-15-200.us-gov-west-1.compute.amazonaws.com",
    "sudo": true,
    "input_file": {
      "bucket": "inspec-profiles-bucket-dev-28wd",
      "key": "rhel7-stig-baseline-master-disable-slow-controls.yml"
    }
  }
}
```

### RedHat 7 STIG Baseline (SSH via SSM)
```json
{
  "results_bucket": "inspec-results-bucket",
  "ssh_key_ssm_param": "/inspec/test-ssh-key",
  "profile": "https://github.com/mitre/redhat-enterprise-linux-7-stig-baseline.git",
  "profile_common_name": "redhat-enterprise-linux-7-stig-baseline-master",
  "config": {
    "target": "ssh://ec2-user@i-00f1868f8f3b4cc03",
    "input": [
      "disable_slow_controls=true"
    ],
    "sudo": true
  }
}
```

### PostgreSQL 12 STIG Baseline (TODO)
```json
"https://github.com/mitre/aws-rds-crunchy-data-postgresql-9-stig-baseline"
```

### Windows Server 2019 STIG Baseline (WinRM)
```json
{
  "results_bucket": "inspec-results-bucket",
  "profile": "https://github.com/mitre/microsoft-windows-server-2019-stig-baseline.git",
  "profile_common_name": "microsoft-windows-server-2019-stig-baseline",
  "config": {
    "target": "winrm://ec2-160.us-gov-west-1.compute.amazonaws.com",
    "user": "Administrator",
    "password": {
      "instance_id": "i-00f1868f8f3b4cc03",
      "launch_key": "/inspec/test-ssh-key"
    }
  }
}
```

### Windows Server 2019 STIG Baseline (WinRM via SSM Port Forwarding)
```json
{
  "results_bucket": "inspec-results-bucket-dev-28wd",
  "profile": "https://github.com/mitre/microsoft-windows-server-2019-stig-baseline.git",
  "profile_common_name": "microsoft-windows-server-2019-stig-baseline",
  "config": {
    "target": "winrm://i-0e35ab216355084ee",
    "user": "Administrator",
    "password": {
      "instance_id": "i-0e35ab216355084ee",
      "launch_key": "/inspec/test-ssh-key"
    }
  }
}
```

## Where Do The Results Go?
If you DO NOT specify the `results_bucket` parameter in the lambda event, then the results will just be logged to CloudWatch. If you DO specify the `results_bucket` parameter in the lambda event, then the lambda will attempt to save the results JSON to the S3 bucket under `unprocessed/*`. The format of the JSON is meant to be a incomplete API call to push results to a Heimdall Server and looks like this:
```javascript
{
  "data": {}, // this contains the HDF results
  "eval_tags": "ServerlessInspec"
}
```

## How Do I Store and Specify an SSH Key for a Scan?
SSH keys for this lambda are expected to be stored in an Secure String parameter within Systems Manager's Parameter Store. Note that if you are trying to scan against an AWS-provided EC2 instance, then you will likely want to save the public key material to `/ec2-user/.ssh/authorized_keys` on the instance.

If you are encrypting the Secure String parameter with something other than the default KMS key (this is recommended), then you will need to ensure that the lambda's IAM role has permissions to execute `kms:Decrypt` against your KMS key.

## How can I specify `--target`? 
If you omit the `config['target']` argument, then InSpec will attempt to execute the profile against the lambda itself.

#### Connecting to SSM Managed EC2 Instance
One additional feature that this lambda provides on top of standard InSpec is that it allows you to establish an SSH or WinRM session for an InSpec scan tunneled through SSM. This is especially useful if the lambda does not have direct network access to its target, but can have a connection through SSM. You can read more about SSM Managed Instance sessions [here](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-sessions-start.html)

You can make an EC2 instance a SSM managed instance using [this guide](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-setting-up.html). This also requires that your EC2 instance has the SSM agent software installed on it. Some AWS-provided images already have this installed, but if it is not already installed on you instance then you can use [this guide](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-setting-up.html) to get it installed. Note that tunneling through SSM for an SSH or WinRM session still requires that you have the credentials to authenticate to the instance.

Note that you aren't limited to just scanning AWS resources, as long as the lambda has access to the internet, then it can scan any resource that you would scan with a normal `inspec exec` command.

### SSH
```json
{
  "...": "...",
  "config": {
    "target": "ssh://ec2-user@somednsname.aws.com"
  }
}
```

### SSH (Tunneled Through SSM)
The difference with this example and the one above is that the `target` is the instance ID of the EC2 instance. This tells the lambda to use a [SSM SSH connection](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-getting-started-enable-ssh-connections.html) to tunnel the SSH connection. This is particularly useful if there is not direct network access to the EC2 isntance, but both the lambda and EC2 instance have access to SSM. Note that this also requires that your EC2 instance be a SSM managed instance.
```json
{
  "...": "...",
  "config": {
    "target": "ssh://ec2-user@i-00f1868f8f3b4cc03"
  }
}
```

### WinRM
```json
{
  "...": "...",
  "config": {
    "target": "ssh://ec2-user@somednsname.aws.com"
  }
}
```

### WinRM (Tunneled Through SSM)
The difference with this example and the one above is that the `target` is the instance ID of the EC2 instance. This tells the lambda to use [SSM port forwarding](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-sessions-start.html) to tunnel the WinRM connection. This is particularly useful if there is not direct network access to the EC2 isntance, but both the lambda and EC2 instance have access to SSM. Note that this also requires that your EC2 instance be a SSM managed instance.
```json
{
  "...": "...",
  "config": {
    "target": "ssh://ec2-user@i-00f1868f8f3b4cc03"
  }
}
```

### AWS
```json
{
  "...": "...",
  "config": {
    "target": "aws://"
  }
}
```

## How can I specify which profile to execute?
Profile sources are documented by InSpec [here](https://docs.chef.io/inspec/cli/#exec).

### Zipped folder on S3 Bucket
In addition to what is already allowed by the vanilla InSpec exec command, you are able to specify a file from an AWS bucket that may be private that the lambda has permissions to access via the AWS API.

If the bucket is not public, you must provide the proper permissions to the lambda's IAM role! This also supports `tar.gz` format.
```json
{
  "...": "...",
  "profile": {
    "bucket": "inspec-profiles-bucket",
    "key": "profiles/inspec-profile.zip"
  }
}
```

### GitHub Repository
```json
{
  "...": "...",
  "profile": "https://github.com/mitre/demo-aws-baseline.git"
}
```

### Web hosted
```json
{
  "...": "...",
  "profile": "https://username:password@webserver/linux-baseline.tar.gz"
}
```

### Chef Supermarket
(This hasn't been tested yet!)
```json
{
  "...": "...",
  "profile": "supermarket://username/linux-baseline"
}
```

## How can I run profiles with dependencies in an offline environment?
The recommendation for offline environments is to save vendored InSpec profiles to an S3 bucket.

```bash
git clone git@github.com:mitre/aws-foundations-cis-baseline.git
inspec vendor ./aws-foundations-cis-baseline && inspec archive ./aws-foundations-cis-baseline
# Then upload ./aws-foundations-cis-baseline.tar.gz to you S3 bucket
```

## How can I specify `--input-file`?
You can read more about InSpec inputs [here](https://docs.chef.io/inspec/inputs/)

### File on S3 Bucket
Note that you must ensure that the lambda's IAM role has permissions to get objects for the specified bucket.
```json
{
  "...": "...",
  "config": {
    "bucket": "inspec-profiles-bucket",
    "key": "input_files/custom-inspec.yml"
  }
}
```

### SecureString SSM Parameter
Note that you must ensure that the lambda's IAM role has permission to the parameter as well as its KMS key to properly fetch & decrypt.
```json
{
  "...": "...",
  "config": {
    "input_file": {
      "ssm_secure_string": "inspec/input_file/param"
    }
  }
}
```

## How can I Specify `--input`?

```json
{
  "...": "...",
  "config": {
    "input": [
      "disable_slow_controls=true",
      "other_input=value"
    ]
  }
}
```

## What other kinds of configurations can I specify?

```javascript
{
  "ssh_key_ssm_param": "/inspec/test-ssh-key", // --key-files / -ia
  "config": {
    "user": "username", // --user
    "self_signed": true, // --self-signed
    "sudo": true, // --sudo
    "bastion_host": "BASTION_HOST", // --bastion-host
    "bastion_port": "BASTION_PORT", // --bastion-port
    "bastion_user": "BASTION_USER" // --bastion-user
  }
}
```

## Where Can I Read More about the InSpec Config?
You can read more about InSpec configuraitons [here](https://docs.chef.io/inspec/config/) and about InSpec reporters [here](https://docs.chef.io/inspec/reporters/). There are some configuration items that are always overridden so that the lambda can work properly - like the reporter, logger, and type.

InSpec doesn't necessarily document the configuration futher than this (to aid easier use of InSpec from Ruby code and not the CLI). The workaround for this was to add an interactive debugger (or even just a `puts conf` statement) to the InSpec Runner source code on a local develeopment machine (found under `/<gem source>/inspec-core-4.37.17/lib/inspec/runner.rb#initialize`). Once the interactive debugger is in place, you can specify InSpec CLI commands as you normally would and view how the configuration is affected. You can find the location of the inspec gem source by running `gem which inspec`.

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

This software was produced for the U. S. Government under Contract Number HHSM-500-2012-00008I, and is subject to Federal Acquisition Regulation Clause 52.227-14, Rights in Data-General.

No other use other than that granted to the U. S. Government, or to those acting on behalf of the U. S. Government under that Clause is authorized without the express written permission of The MITRE Corporation.
