variable "aws_region" {
  type    = string
  default = "eu-central-1"
}

variable "project_name" {
  type    = string
  default = "simple-app"
}

variable "instance_type" {
  type    = string
  default = "t2.micro"
}

variable "cloudfront_aliases" {
  type        = list(string)
  default     = []
}

variable "acm_cert_arn_us_east_1" {
  type        = string
  default     = ""
}
