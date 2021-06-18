# Example Terraform Deployment

The below is an example terraform configuration that is able to deploy the serverless-inspec-lambda function and provide
 its IAM role with sufficient permissions to complete many common tasks. 

**Note that the permissions provided to this example IAM role are quite open and it is highly recommended that you tweak
 these so that your lambda runner has the minimum required permissions!**

 Before deploying with terraform you will need to pull the docker image to your deployment machine
```bash
docker pull ghcr.io/mitre/serverless-inspec-lambda:<version>
```

```hcl
##
# InSpec Role to Invoke InSpec Lambda function 
#
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role
#
resource "aws_iam_role" "InSpecRole" {
  name = "InSpecRole-${var.deployment_id}"

  # Allow execution of the lambda function
  # User: is not authorized to perform: iam:ListPolicies on resource: policy path /
  # Should NOT have AWS Config Write access
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole",
    "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole",
    "arn:aws-us-gov:iam::aws:policy/service-role/AWSConfigRole"
  ]

  # Allow assume role permission for lambda
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })

  # Allow S3 read access to InSpec profile bucket
  inline_policy {
    name = "S3ProfileAccess"

    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Action = [
            "s3:GetObject"
          ]
          Effect   = "Allow"
          Resource = "${var.profiles_bucket_arn}/*"
        }
      ]
    })
  }

  # Allow S3 write access to InSpec results bucket
  inline_policy {
    name = "S3ResultsAccess"

    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Action = [
            "s3:PutObject"
          ]
          Effect   = "Allow"
          Resource = "${var.results_bucket_arn}/*"
        }
      ]
    })
  }

  # Allow SSM access for starting sessions and SSM parameters
  inline_policy {
    name = "SsmParamAndSessionAccess"

    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Action = [
            "ssm:GetParameter",
            "ssm:StartSession"
          ]
          Effect   = "Allow"
          Resource = "*" # consider locking this down to a GetParameter subpath
        }
      ]
    })
  }

  # Allow EC2 get password data for fetching WinRM credentials
  inline_policy {
    name = "EC2GetPasswordDataAccess"

    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Action = [
            "ec2:GetPasswordData"
          ]
          Effect   = "Allow"
          Resource = "*" # consider locking this down to a specific groups of machines
        }
      ]
    })
  }

  inline_policy {
    name = "AllowHeimdallPassKmsKeyDecrypt"

    policy = jsonencode({
      Version = "2012-10-17"
      Statement = [
        {
          Action = [
            "kms:Decrypt"
          ]
          Effect   = "Allow"
          Resource = "*" # consider locking this down to specific key(s)
        }
      ]
    })
  }
}

##
# InSpec Lambda function
#
# https://registry.terraform.io/modules/terraform-aws-modules/lambda/aws/latest
#
module "serverless-inspec-lambda" {
  source = "github.com/mitre/serverless-inspec-lambda"
  subnet_ids      = ["subnet-00000000000000000"]
  security_groups = ["sg-00000000000000000"]
  lambda_role_arn = aws_iam_role.InSpecRole.arn
  lambda_name     = "serverless-inspec-lambda"
}
```