data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "aws_vpc" "aws_vpc_id" {
  id = "vpc-1234567890123"
}
