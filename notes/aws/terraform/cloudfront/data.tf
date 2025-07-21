data "aws_acm_certificate" "nodestack" {
  provider = aws.us-east-1

  domain   = "*.nodestack.ca"
  statuses = ["ISSUED"]
}
