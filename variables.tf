
variable "subnet_ids" {
  description = "The subnet ids to deploy the lambda to."
  type        = list(string)
  default     = null
}

variable "security_groups" {
  description = "The security groups to assign to the lambda."
  type        = list(string)
  default     = null
}

variable "image_version" {
  description = "The image and tag of the lambda docker image to deploy"
  type = string
  default = null
}

variable "lambda_role_arn" {
  description = "The ARN for the IAM role that will be assigned to the lambda"
  type = string
  default = ""
}

variable "cloudwatch_logs_kms_key_id" {
  description = "The ARN of the KMS key to use for lambda log encryption."
  type        = string
  default     = null
}

variable "lambda_name" {
  description = "The name of the lambda function"
  type = string
  default = "serverless-inspec-lambda"
}
