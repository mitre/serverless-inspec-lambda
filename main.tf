
##
# Computed local variables
#
locals {
  # If image_version is not set, then default to the lastest available version
  image_version = var.image_version != null ? var.image_version : file("${path.module}/version")
}

# Elastic Container Registry for SAF deployment
#
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/ecr_repository
#
resource "aws_ecr_repository" "mitre_serverless_inspec" {
  name                 = "mitre/serverless-inspec-lambda"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

##
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region
#
data "aws_region" "current" {}

##
# https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity
#
data "aws_caller_identity" "current" {}

resource "null_resource" "push_image" {
  depends_on = [
    aws_ecr_repository.mitre_serverless_inspec,
  ]

  # Ensures this script always runs
  triggers = {
    always_run = timestamp()
  }

  # https://www.terraform.io/docs/language/resources/provisioners/local-exec.html
  provisioner "local-exec" {
    command = "${path.module}/push-image.sh"

    environment = {
      REPOSITORY_URL = aws_ecr_repository.mitre_serverless_inspec.repository_url
      AWS_REGION     = data.aws_region.current.name
      AWS_ACCOUNT_ID = data.aws_caller_identity.current.account_id
      REPO_NAME      = "ghcr.io/mitre/serverless-inspec-lambda"
      IMAGE_TAG      = local.image_version
    }
  }
}

##
# InSpec Lambda function
#
# https://registry.terraform.io/modules/terraform-aws-modules/lambda/aws/latest
#
module "serverless-inspec-lambda" {
  source = "terraform-aws-modules/lambda/aws"
  depends_on = [
    null_resource.push_image
  ]

  function_name = var.lambda_name
  description   = "Lambda capable of performing InSpec scans."
  handler       = "lambda_function.lambda_handler"
  runtime       = "ruby2.7"
  create_role   = false
  lambda_role   = var.lambda_role_arn
  timeout       = 900
  memory_size   = 1024

  vpc_subnet_ids         = var.subnet_ids
  vpc_security_group_ids = var.security_groups

  create_package = false
  image_uri      = "${aws_ecr_repository.mitre_serverless_inspec.repository_url}:${local.image_version}"
  package_type   = "Image"

  environment_variables = {
    HOME = "/tmp"
  }
}
